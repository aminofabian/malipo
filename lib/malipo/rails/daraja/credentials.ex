defmodule Malipo.Rails.Daraja.Credentials do
  @moduledoc """
  Normalise and validate a Daraja credentials map.

  Accepts either string or atom keys (Java-style camelCase or snake_case).
  Passkey whitespace is stripped once here so push / query / validate cannot diverge.
  """

  alias Malipo.Rails.Failure

  @sandbox_passkey "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919"
  @sandbox_base "https://sandbox.safaricom.co.ke"
  @production_base "https://api.safaricom.co.ke"

  @type t :: %{
          consumer_key: String.t(),
          consumer_secret: String.t(),
          shortcode: String.t(),
          passkey: String.t(),
          environment: :sandbox | :production,
          shortcode_type: :paybill | :till,
          party_b: String.t(),
          base_url: String.t(),
          transaction_type: String.t() | nil,
          account_reference: String.t() | nil
        }

  @spec normalise(map()) :: {:ok, t()} | {:error, Failure.t()}
  def normalise(raw) when is_map(raw) do
    m = stringify(raw)

    with {:ok, key} <- required(m, ["consumer_key", "consumerKey"]),
         {:ok, secret} <- required(m, ["consumer_secret", "consumerSecret"]),
         {:ok, shortcode} <- required_shortcode(m),
         {:ok, passkey} <- required_passkey(m) do
      env = environment(m)
      party_b = party_b(m, shortcode)
      type = shortcode_type(m)

      cond do
        sandbox_passkey?(passkey) and env == :production ->
          {:error,
           Failure.new(
             :bad_passkey,
             "Sandbox passkey on a production shortcode — paste the Go Live passkey for #{shortcode}",
             retryable?: false
           )}

        true ->
          {:ok,
           %{
             consumer_key: key,
             consumer_secret: secret,
             shortcode: shortcode,
             passkey: passkey,
             environment: env,
             shortcode_type: type,
             party_b: party_b,
             base_url: base_url(m, env),
             transaction_type: first(m, ["transaction_type", "transactionType", "TransactionType"]),
             account_reference: first(m, ["account_reference", "accountReference"])
           }}
      end
    end
  end

  def normalise(_), do: {:error, Failure.new(:bad_credentials, "Credentials must be a map", retryable?: false)}

  @spec sandbox_passkey?(String.t()) :: boolean()
  def sandbox_passkey?(passkey) when is_binary(passkey) do
    String.downcase(passkey) == @sandbox_passkey
  end

  @spec transaction_type(t()) :: String.t()
  def transaction_type(%{transaction_type: explicit} = creds) when is_binary(explicit) do
    t = String.trim(explicit)

    cond do
      String.match?(t, ~r/^(CustomerBuyGoodsOnline|buygoods|till)$/i) ->
        "CustomerBuyGoodsOnline"

      String.match?(t, ~r/^(CustomerPayBillOnline|paybill)$/i) ->
        "CustomerPayBillOnline"

      true ->
        default_transaction_type(creds)
    end
  end

  def transaction_type(creds), do: default_transaction_type(creds)

  defp default_transaction_type(%{shortcode: sc, party_b: party_b, shortcode_type: type}) do
    cond do
      party_b != sc -> "CustomerBuyGoodsOnline"
      type == :till -> "CustomerBuyGoodsOnline"
      true -> "CustomerPayBillOnline"
    end
  end

  defp required_shortcode(m) do
    case first(m, ["shortcode", "tillNumber", "till_number", "businessShortCode", "business_short_code"]) do
      nil ->
        {:error, Failure.new(:bad_credentials, "shortcode is required", retryable?: false)}

      raw ->
        digits = digits_only(raw)

        if digits && String.match?(digits, ~r/^\d{5,7}$/) do
          {:ok, digits}
        else
          {:error,
           Failure.new(:bad_credentials, "BusinessShortCode must be 5–7 digits", retryable?: false)}
        end
    end
  end

  defp required_passkey(m) do
    case first(m, ["passkey", "Passkey", "lipa_na_mpesa_passkey"]) do
      nil ->
        {:error, Failure.new(:bad_passkey, "Lipa Na M-Pesa passkey is required", retryable?: false)}

      raw ->
        cleaned = Regex.replace(~r/\s+/, raw, "")

        if cleaned == "" do
          {:error, Failure.new(:bad_passkey, "Lipa Na M-Pesa passkey is required", retryable?: false)}
        else
          {:ok, cleaned}
        end
    end
  end

  defp party_b(m, shortcode) do
    case first(m, ["party_b", "partyB", "PartyB", "receivingShortcode", "receiving_shortcode"]) do
      nil ->
        shortcode

      raw ->
        case digits_only(raw) do
          digits when is_binary(digits) and byte_size(digits) in 5..7 -> digits
          _ -> shortcode
        end
    end
  end

  defp shortcode_type(m) do
    case first(m, ["shortcode_type", "shortcodeType", "type"]) do
      nil ->
        :paybill

      raw ->
        t = String.downcase(String.trim(raw))

        if t in ["till", "buygoods", "buy_goods"] do
          :till
        else
          :paybill
        end
    end
  end

  defp environment(m) do
    case first(m, ["environment", "env"]) do
      nil -> :sandbox
      raw -> if String.downcase(String.trim(raw)) == "production", do: :production, else: :sandbox
    end
  end

  defp base_url(m, env) do
    case first(m, ["base_url", "baseUrl"]) do
      nil -> if(env == :production, do: @production_base, else: @sandbox_base)
      url -> String.trim_trailing(url, "/")
    end
  end

  defp required(m, keys) do
    case first(m, keys) do
      nil ->
        {:error,
         Failure.new(:bad_credentials, "consumerKey and consumerSecret are required",
           retryable?: false
         )}

      value ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error,
           Failure.new(:bad_credentials, "consumerKey and consumerSecret are required",
             retryable?: false
           )}
        else
          {:ok, trimmed}
        end
    end
  end

  defp first(m, keys) do
    Enum.find_value(keys, fn k ->
      case Map.get(m, k) do
        v when is_binary(v) and v != "" -> v
        v when is_integer(v) -> Integer.to_string(v)
        _ -> nil
      end
    end)
  end

  defp digits_only(nil), do: nil

  defp digits_only(raw) when is_binary(raw) do
    digits = Regex.replace(~r/\D/, raw, "")
    if digits == "", do: nil, else: digits
  end

  defp stringify(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
