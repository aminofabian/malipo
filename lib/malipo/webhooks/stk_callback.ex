defmodule Malipo.Webhooks.StkCallback do
  @moduledoc """
  Parse Daraja STK callback JSON into a classified outcome.
  """

  alias Malipo.Rails.Classify
  alias Malipo.Rails.Failure

  @type outcome ::
          {:success, %{checkout_request_id: String.t(), receipt: String.t(), raw: map()}}
          | {:failed, %{checkout_request_id: String.t(), failure: Failure.t(), raw: map()}}
          | {:pending, %{checkout_request_id: String.t() | nil, raw: map()}}
          | {:error, :invalid_payload}

  @spec parse(map() | String.t()) :: outcome()
  def parse(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} -> parse(map)
      {:error, _} -> {:error, :invalid_payload}
    end
  end

  def parse(payload) when is_map(payload) do
    stk = get_in(payload, ["Body", "stkCallback"]) || payload["stkCallback"] || %{}

    checkout = text(stk, "CheckoutRequestID")
    code = text(stk, "ResultCode")
    desc = text(stk, "ResultDesc") || ""
    receipt = metadata_value(stk, "MpesaReceiptNumber")

    cond do
      is_nil(checkout) or checkout == "" ->
        {:error, :invalid_payload}

      code in ["0", "00"] and present?(receipt) ->
        {:success,
         %{
           checkout_request_id: checkout,
           merchant_request_id: text(stk, "MerchantRequestID"),
           receipt: receipt,
           amount: metadata_value(stk, "Amount"),
           phone: metadata_value(stk, "PhoneNumber"),
           raw: payload
         }}

      code in ["0", "00"] ->
        # Success without receipt — treat as pending until poll/receipt arrives.
        {:pending, %{checkout_request_id: checkout, raw: payload}}

      true ->
        case Classify.query_bucket(code, desc) do
          :pending ->
            {:pending, %{checkout_request_id: checkout, raw: payload}}

          :success ->
            {:pending, %{checkout_request_id: checkout, raw: payload}}

          :failed ->
            failure = Classify.daraja(code, desc, payload)

            {:failed,
             %{
               checkout_request_id: checkout,
               merchant_request_id: text(stk, "MerchantRequestID"),
               failure: failure,
               raw: payload
             }}
        end
    end
  end

  def parse(_), do: {:error, :invalid_payload}

  @doc "Extract CheckoutRequestID for dedupe without full parse."
  @spec dedupe_key(map() | String.t()) :: String.t() | nil
  def dedupe_key(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} -> dedupe_key(map)
      _ -> nil
    end
  end

  def dedupe_key(payload) when is_map(payload) do
    stk = get_in(payload, ["Body", "stkCallback"]) || payload["stkCallback"] || %{}
    text(stk, "CheckoutRequestID")
  end

  def dedupe_key(_), do: nil

  defp metadata_value(stk, name) when is_map(stk) and is_binary(name) do
    items =
      get_in(stk, ["CallbackMetadata", "Item"]) ||
        get_in(stk, ["CallbackMetadata", "item"]) ||
        []

    items
    |> List.wrap()
    |> Enum.find_value(fn
      %{"Name" => ^name, "Value" => v} -> to_string(v)
      %{"name" => n, "value" => v} -> if n == name, do: to_string(v)
      _ -> nil
    end)
  end

  defp text(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil -> nil
      v -> v |> to_string() |> String.trim()
    end
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false
end
