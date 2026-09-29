defmodule Malipo.Webhooks.C2bCallback do
  @moduledoc """
  Parse Daraja C2B confirmation / validation JSON.
  """

  alias Malipo.Msisdn

  @type parsed :: %{
          trans_id: String.t(),
          amount: Decimal.t(),
          shortcode: String.t() | nil,
          bill_ref: String.t() | nil,
          payer_msisdn: String.t() | nil,
          payer_name: String.t() | nil,
          transaction_type: String.t() | nil,
          trans_time: String.t() | nil,
          raw: map()
        }

  @spec parse(map() | String.t()) :: {:ok, parsed()} | {:error, :invalid_payload}
  def parse(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} -> parse(map)
      _ -> {:error, :invalid_payload}
    end
  end

  def parse(payload) when is_map(payload) do
    trans_id = text(payload, "TransID") || text(payload, "TransactionID")
    amount_raw = text(payload, "TransAmount") || text(payload, "Amount")

    with true <- present?(trans_id),
         {:ok, amount} <- parse_amount(amount_raw) do
      phone_raw = text(payload, "MSISDN") || text(payload, "PhoneNumber")
      phone =
        case phone_raw && Msisdn.normalise(phone_raw) do
          {:ok, msisdn} -> msisdn
          _ -> phone_raw
        end

      name =
        [text(payload, "FirstName"), text(payload, "MiddleName"), text(payload, "LastName")]
        |> Enum.reject(&(is_nil(&1) or &1 == ""))
        |> Enum.join(" ")
        |> case do
          "" -> nil
          n -> n
        end

      {:ok,
       %{
         trans_id: trans_id,
         amount: amount,
         shortcode: text(payload, "BusinessShortCode") || text(payload, "ShortCode"),
         bill_ref: text(payload, "BillRefNumber") || text(payload, "AccountReference"),
         payer_msisdn: phone,
         payer_name: name,
         transaction_type: text(payload, "TransactionType"),
         trans_time: text(payload, "TransTime"),
         raw: payload
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  def parse(_), do: {:error, :invalid_payload}

  @spec dedupe_key(map() | String.t()) :: String.t() | nil
  def dedupe_key(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} -> dedupe_key(map)
      _ -> nil
    end
  end

  def dedupe_key(payload) when is_map(payload) do
    text(payload, "TransID") || text(payload, "TransactionID")
  end

  def dedupe_key(_), do: nil

  defp parse_amount(nil), do: {:error, :invalid_amount}
  defp parse_amount(""), do: {:error, :invalid_amount}

  defp parse_amount(raw) when is_binary(raw) do
    case Decimal.parse(String.trim(raw)) do
      {d, _} ->
        if Decimal.positive?(d), do: {:ok, d}, else: {:error, :invalid_amount}

      :error ->
        {:error, :invalid_amount}
    end
  end

  defp parse_amount(n) when is_integer(n) or is_float(n) do
    d = Decimal.new(n)
    if Decimal.positive?(d), do: {:ok, d}, else: {:error, :invalid_amount}
  end

  defp text(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil -> nil
      v ->
        s = v |> to_string() |> String.trim()
        if s == "", do: nil, else: s
    end
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false
end
