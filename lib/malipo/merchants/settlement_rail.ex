defmodule Malipo.Merchants.SettlementRail do
  @moduledoc """
  Map a settlement destination onto Daraja STK fields.

  Platform shortcode + passkey still sign the request; `PartyB` and
  `TransactionType` route the payment to the merchant (same as Java
  `CUSTODY_MPESA` / `MANUAL`).
  """

  alias Malipo.Merchants
  alias Malipo.Merchants.Destination

  @doc """
  Resolve STK overrides for an intent push.

  Priority: explicit `context` / request destination → Connect DB row for `business_id`.
  """
  @spec overrides_for_push(map() | nil, String.t()) ::
          {:ok, map()} | {:error, :destination_inactive | :invalid_destination} | :skip
  def overrides_for_push(context, business_id) when is_binary(business_id) do
    context = context || %{}

    case overrides_from_context(context) do
      {:ok, _} = ok ->
        ok

      :skip ->
        overrides_from_business_id(business_id)

      {:error, _} = err ->
        err
    end
  end

  @spec stk_push_overrides(Destination.t()) ::
          {:ok, map()} | {:error, :invalid_destination}
  def stk_push_overrides(%Destination{kind: "till", till_number: till} = dest)
      when is_binary(till) and till != "" do
    if destination_usable?(dest) do
      {:ok, %{party_b: till, transaction_type: "CustomerBuyGoodsOnline"}}
    else
      {:error, :destination_inactive}
    end
  end

  def stk_push_overrides(%Destination{
        kind: kind,
        paybill_number: paybill,
        account_number: account
      } = dest)
      when kind in ["paybill", "bank"] and is_binary(paybill) and paybill != "" and
             is_binary(account) and account != "" do
    if destination_usable?(dest) do
      {:ok,
       %{
         party_b: paybill,
         transaction_type: "CustomerPayBillOnline",
         account_reference: account
       }}
    else
      {:error, :destination_inactive}
    end
  end

  def stk_push_overrides(_), do: {:error, :invalid_destination}

  @doc "Normalise a destination map from intent API / Java displayInstructions shape."
  @spec overrides_from_map(map()) :: {:ok, map()} | :skip | {:error, :invalid_destination}
  def overrides_from_map(map) when is_map(map) do
    map = stringify(map)

    kind =
      map["kind"] ||
        map["type"] ||
        infer_kind(map)

    case kind do
      "till" ->
        till = digits(map["till_number"] || map["tillNumber"] || map["till"])

        if till do
          {:ok, %{party_b: till, transaction_type: "CustomerBuyGoodsOnline"}}
        else
          {:error, :invalid_destination}
        end

      k when k in ["paybill", "bank"] ->
        paybill = digits(map["paybill_number"] || map["paybillNumber"] || map["paybill"])
        account = text(map["account_number"] || map["accountNumber"] || map["account"])

        if paybill && account do
          {:ok,
           %{
             party_b: paybill,
             transaction_type: "CustomerPayBillOnline",
             account_reference: account
           }}
        else
          {:error, :invalid_destination}
        end

      _ ->
        case party_b_only(map) do
          nil -> :skip
          party_b -> {:ok, party_b}
        end
    end
  end

  def overrides_from_map(_), do: :skip

  defp overrides_from_context(context) do
    context = stringify(context)

    cond do
      is_map(context["settlement_destination"]) ->
        overrides_from_map(context["settlement_destination"])

      is_map(context["destination"]) ->
        overrides_from_map(context["destination"])

      true ->
        case party_b_only(context) do
          nil -> :skip
          party_b -> {:ok, party_b}
        end
    end
  end

  defp overrides_from_business_id(business_id) do
    case Merchants.get_active_destination(business_id) do
      %Destination{} = dest ->
        case stk_push_overrides(dest) do
          {:ok, _} = ok -> ok
          {:error, :destination_inactive} -> {:error, :destination_inactive}
          {:error, :invalid_destination} -> {:error, :invalid_destination}
        end

      nil ->
        if Merchants.list_for_business(business_id) == [] do
          :skip
        else
          {:error, :destination_inactive}
        end
    end
  end

  defp destination_usable?(%Destination{verified: true, active: true}), do: true

  defp destination_usable?(%Destination{verified: true, active: false}), do: false

  defp destination_usable?(_), do: false

  defp party_b_only(map) do
    case digits(map["party_b"] || map["partyB"] || map["PartyB"] || map["receiving_shortcode"]) do
      nil ->
        nil

      party_b ->
        tx =
          map["transaction_type"] ||
            map["transactionType"] ||
            if(party_b != map["shortcode"], do: "CustomerBuyGoodsOnline", else: nil)

        %{party_b: party_b, transaction_type: tx || "CustomerBuyGoodsOnline"}
    end
  end

  defp infer_kind(map) do
    cond do
      digits(map["till_number"] || map["tillNumber"] || map["till"]) -> "till"
      digits(map["paybill_number"] || map["paybillNumber"] || map["paybill"]) -> "paybill"
      true -> nil
    end
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end

  defp digits(nil), do: nil

  defp digits(v) when is_binary(v) do
    d = Regex.replace(~r/\D/, v, "")
    if d == "", do: nil, else: d
  end

  defp digits(v) when is_integer(v), do: Integer.to_string(v)

  defp text(v) when is_binary(v) do
    t = String.trim(v)
    if t == "", do: nil, else: t
  end

  defp text(_), do: nil
end
