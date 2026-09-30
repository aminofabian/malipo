defmodule Malipo.Rails.Daraja do
  @moduledoc """
  Daraja (Safaricom M-Pesa) rail adapter.

  * `validate/1` proves the Lipa passkey via `stkpushquery` — not OAuth alone.
  * `push/2` / `query/2` normalise credentials once, then call Finch.
  """

  @behaviour Malipo.Rails.Rail

  alias Malipo.Msisdn
  alias Malipo.Rails.Classify
  alias Malipo.Rails.Daraja.{Client, Credentials, Password}
  alias Malipo.Rails.Failure

  @impl true
  def validate(raw_creds) do
    with {:ok, creds} <- Credentials.normalise(raw_creds),
         {:ok, _token} <- Client.oauth_token(creds) do
      probe_passkey(creds)
    end
  end

  @impl true
  def push(raw_creds, request) do
    with {:ok, creds} <- Credentials.normalise(raw_creds),
         {:ok, body} <- build_push_body(creds, request),
         {:ok, response} <- Client.stk_push(creds, body) do
      interpret_push(response)
    end
  end

  @impl true
  def query(raw_creds, checkout_request_id)
      when is_binary(checkout_request_id) and checkout_request_id != "" do
    with {:ok, creds} <- Credentials.normalise(raw_creds) do
      timestamp = Password.timestamp(DateTime.utc_now())
      password = Password.build(creds.shortcode, creds.passkey, timestamp)

      body = %{
        "BusinessShortCode" => creds.shortcode,
        "Password" => password,
        "Timestamp" => timestamp,
        "CheckoutRequestID" => checkout_request_id
      }

      with {:ok, response} <- Client.stk_query(creds, body) do
        interpret_query(response)
      end
    end
  end

  def query(_creds, _),
    do: {:error, Failure.new(:unknown, "checkout_request_id is required", retryable?: false)}

  # ── fee sweep (rail movement) ──────────────────────────────────────

  @doc """
  Move money rail-to-rail — a fee sweep to the configured destination.

  Credentials come from the rail; operator fields (`initiator_name`,
  `security_credential`, optional `command_id`) ride along in the same map.
  The command defaults to a goods purchase for till destinations and a
  paybill transfer otherwise.
  """
  @impl true
  def transfer(raw_creds, request) do
    raw = stringify(raw_creds)

    with {:ok, creds} <- Credentials.normalise(raw),
         {:ok, operator} <- operator(raw),
         {:ok, body} <- build_transfer_body(creds, operator, request),
         {:ok, response} <- Client.transfer(creds, body) do
      interpret_transfer(response)
    end
  end

  defp operator(raw) do
    initiator = first_text(raw, ["initiator_name", "initiatorName"])
    credential = first_text(raw, ["security_credential", "securityCredential"])
    command = first_text(raw, ["command_id", "commandId"])

    if initiator && credential do
      {:ok, %{initiator: initiator, credential: credential, command: command}}
    else
      {:error,
       Failure.new(:bad_credentials, "rail is missing its operator credentials",
         retryable?: false
       )}
    end
  end

  defp build_transfer_body(creds, operator, request) do
    request = stringify(request)

    with {:ok, amount} <- amount(request),
         {:ok, receiver} <- transfer_receiver(request),
         {:ok, result_url} <- endpoint_url(request["result_url"], "ResultURL"),
         {:ok, timeout_url} <- endpoint_url(request["timeout_url"], "QueueTimeOutURL") do
      {:ok,
       %{
         "Initiator" => operator.initiator,
         "SecurityCredential" => operator.credential,
         "CommandID" => operator.command || receiver.command,
         "SenderIdentifierType" => "4",
         "RecieverIdentifierType" => receiver.identifier_type,
         "Amount" => amount,
         "PartyA" => creds.shortcode,
         "PartyB" => receiver.code,
         "AccountReference" => account_reference(request["account_reference"]),
         "Remarks" => truncate(request["remarks"] || "Malipo fees", 100),
         "QueueTimeOutURL" => timeout_url,
         "ResultURL" => result_url
       }}
    end
  end

  defp transfer_receiver(request) do
    destination = request["destination"] |> stringify()

    case destination["kind"] do
      "till" ->
        with {:ok, code} <- receiver_code(destination["till"]) do
          {:ok, %{code: code, identifier_type: "2", command: "BusinessBuyGoods"}}
        end

      _ ->
        with {:ok, code} <- receiver_code(destination["paybill"]) do
          {:ok, %{code: code, identifier_type: "4", command: "BusinessPayBill"}}
        end
    end
  end

  defp receiver_code(raw) when is_binary(raw) do
    digits = Regex.replace(~r/\D/, raw, "")

    if byte_size(digits) in 5..7 do
      {:ok, digits}
    else
      {:error,
       Failure.new(:unknown, "fee destination is not a valid shortcode", retryable?: false)}
    end
  end

  defp receiver_code(_),
    do:
      {:error,
       Failure.new(:unknown, "fee destination is not a valid shortcode", retryable?: false)}

  defp endpoint_url(url, label) do
    case url do
      url when is_binary(url) and url != "" ->
        if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
          {:ok, url}
        else
          {:error, Failure.new(:unknown, "#{label} must be a URL", retryable?: false)}
        end

      _ ->
        {:error, Failure.new(:unknown, "#{label} is required", retryable?: false)}
    end
  end

  defp interpret_transfer(response) do
    status = Map.get(response, "_http_status", 0)
    code = text(response, "ResponseCode")
    conversation_id = text(response, "ConversationID")
    originator = text(response, "OriginatorConversationID")
    desc = text(response, "ResponseDescription") || text(response, "errorMessage")
    error_code = text(response, "errorCode")

    if status in 200..299 and code in ["0", "00"] and is_binary(conversation_id) do
      {:ok,
       %{
         conversation_id: conversation_id,
         originator_conversation_id: originator,
         raw: response
       }}
    else
      code = error_code || code || to_string(status)
      {:error, Classify.daraja(code, desc || "transfer declined", response)}
    end
  end

  defp first_text(map, keys) do
    Enum.find_value(keys, fn k ->
      case Map.get(map, k) do
        v when is_binary(v) -> if String.trim(v) == "", do: nil, else: String.trim(v)
        _ -> nil
      end
    end)
  end

  # ── validate probe ─────────────────────────────────────────────────

  defp probe_passkey(creds) do
    timestamp = Password.timestamp(DateTime.utc_now())
    password = Password.build(creds.shortcode, creds.passkey, timestamp)

    body = %{
      "BusinessShortCode" => creds.shortcode,
      "Password" => password,
      "Timestamp" => timestamp,
      "CheckoutRequestID" => "ws_CO_malipo_probe_" <> timestamp
    }

    case Client.stk_query(creds, body) do
      {:ok, response} ->
        error_code = text(response, "errorCode")
        error_message = text(response, "errorMessage") || text(response, "ResultDesc") || ""
        combined = "#{error_code} #{error_message}"

        if Classify.wrong_credentials?(error_message) or Classify.wrong_credentials?(combined) do
          {:error,
           Failure.new(
             :bad_passkey,
             "Lipa Na M-Pesa passkey does not match shortcode #{creds.shortcode}",
             provider_code: error_code,
             retryable?: false,
             raw: response
           )}
        else
          # Transaction-not-found / still-processing / ResultCode → Password accepted.
          :ok
        end

      {:error, %Failure{kind: :provider_unavailable} = failure} ->
        # Honest: do not green-tick after a network blip (unlike the Java adapter).
        {:error,
         Failure.new(:inconclusive, "STK password probe inconclusive — retry",
           retryable?: true,
           raw: failure
         )}

      {:error, failure} ->
        {:error, failure}
    end
  end

  # ── push ───────────────────────────────────────────────────────────

  defp build_push_body(creds, request) do
    request = stringify(request)

    with {:ok, phone} <- phone(request),
         {:ok, amount} <- amount(request),
         {:ok, callback} <- callback_url(request) do
      timestamp = Password.timestamp(DateTime.utc_now())
      password = Password.build(creds.shortcode, creds.passkey, timestamp)
      party_b = party_b_for_push(creds, request)
      effective_creds = %{creds | party_b: party_b}

      tx_type =
        case first_text(request, ["transaction_type", "transactionType"]) do
          nil -> Credentials.transaction_type(effective_creds)
          type -> type
        end

      account_ref =
        account_reference(request["account_reference"] || creds.account_reference)

      desc = truncate(request["transaction_desc"] || request["description"] || "Payment", 13)

      {:ok,
       %{
         "BusinessShortCode" => creds.shortcode,
         "Password" => password,
         "Timestamp" => timestamp,
         "TransactionType" => tx_type,
         "Amount" => amount,
         "PartyA" => phone,
         "PartyB" => party_b,
         "PhoneNumber" => phone,
         "CallBackURL" => callback,
         "AccountReference" => account_ref,
         "TransactionDesc" => desc
       }}
    end
  end

  defp interpret_push(response) do
    status = Map.get(response, "_http_status", 0)
    response_code = text(response, "ResponseCode")
    checkout_id = text(response, "CheckoutRequestID")
    merchant_id = text(response, "MerchantRequestID")
    desc = text(response, "ResponseDescription") || text(response, "errorMessage")
    error_code = text(response, "errorCode")

    cond do
      status in 200..299 and (response_code in ["0", "00"] or checkout_id != nil) and
          checkout_id != nil ->
        {:ok,
         %{
           checkout_request_id: checkout_id,
           merchant_request_id: merchant_id,
           raw: response
         }}

      true ->
        code = error_code || response_code || to_string(status)
        message = desc || "STK request declined"

        failure =
          if Classify.wrong_credentials?(message) do
            Failure.new(:bad_passkey, message,
              provider_code: code,
              retryable?: false,
              raw: response
            )
          else
            Classify.daraja(code, message, response)
          end

        {:error, failure}
    end
  end

  # ── query ──────────────────────────────────────────────────────────

  defp interpret_query(response) do
    # While the prompt is on the handset Daraja often answers with errorCode
    # instead of ResultCode — treat that as pending, not failed.
    error_code = text(response, "errorCode")

    if error_code do
      message = text(response, "errorMessage") || "Still processing"

      if Classify.wrong_credentials?(message) do
        {:error,
         Failure.new(:bad_passkey, message,
           provider_code: error_code,
           retryable?: false,
           raw: response
         )}
      else
        {:ok,
         %{
           outcome: :pending,
           result_code: error_code,
           result_desc: message,
           receipt: nil,
           amount: nil,
           phone: nil,
           raw: response
         }}
      end
    else
      result_code = text(response, "ResultCode") || text(response, "ResponseCode")
      result_desc = text(response, "ResultDesc") || text(response, "ResponseDescription")
      outcome = Classify.query_bucket(result_code, result_desc)

      result = %{
        outcome: outcome,
        result_code: result_code,
        result_desc: result_desc,
        receipt: text(response, "MpesaReceiptNumber") || callback_receipt(response),
        amount: parse_amount(text(response, "Amount")),
        phone: text(response, "PhoneNumber"),
        raw: response
      }

      case outcome do
        :failed ->
          {:error, Classify.daraja(result_code, result_desc, response)}

        _ ->
          {:ok, result}
      end
    end
  end

  defp callback_receipt(response) do
    # Some query payloads nest metadata; keep nil when absent.
    get_in(response, ["CallbackMetadata", "Item"])
    |> case do
      items when is_list(items) ->
        Enum.find_value(items, fn
          %{"Name" => "MpesaReceiptNumber", "Value" => v} -> to_string(v)
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  # ── request helpers ────────────────────────────────────────────────

  defp phone(request) do
    raw = request["phone"] || request["phone_number"] || request["payer_msisdn"]

    case Msisdn.normalise(raw) do
      {:ok, msisdn} ->
        {:ok, msisdn}

      {:error, :invalid_phone} ->
        {:error, Failure.new(:invalid_phone, "phoneNumber is required", retryable?: false)}
    end
  end

  defp amount(request) do
    raw = request["amount"]

    decimal =
      cond do
        match?(%Decimal{}, raw) -> raw
        is_integer(raw) -> Decimal.new(raw)
        is_float(raw) -> Decimal.from_float(raw)
        is_binary(raw) -> Decimal.new(raw)
        true -> nil
      end

    cond do
      is_nil(decimal) ->
        {:error, Failure.new(:invalid_amount, "amount must be at least 1", retryable?: false)}

      Decimal.compare(decimal, 0) != :gt ->
        {:error, Failure.new(:invalid_amount, "amount must be at least 1", retryable?: false)}

      true ->
        # Daraja Amount is an integer KES.
        {:ok, decimal |> Decimal.round(0) |> Decimal.to_integer()}
    end
  end

  defp callback_url(request) do
    case request["callback_url"] || request["callbackBaseUrl"] do
      url when is_binary(url) and url != "" ->
        base = String.trim_trailing(url, "/")

        if String.ends_with?(base, "/webhooks/daraja/stk") do
          {:ok, base}
        else
          {:ok, base <> "/webhooks/daraja/stk"}
        end

      _ ->
        {:error, Failure.new(:unknown, "callback_url is required", retryable?: false)}
    end
  end

  defp party_b_for_push(creds, request) do
    case first_text(request, ["party_b", "partyB", "PartyB"]) do
      nil -> creds.party_b
      code -> code
    end
  end

  defp account_reference(nil), do: "Kiosk"

  # Daraja wants alphanumerics only. Do **not** truncate: for a bank/paybill
  # settlement the account reference *is* the destination, so dropping the tail
  # (e.g. an account number ending in zeros) silently pays the wrong account.
  # Send it whole and let Daraja reject it if it is genuinely unusable.
  defp account_reference(raw) when is_binary(raw) do
    cleaned = Regex.replace(~r/[^A-Za-z0-9]/, raw, "")
    if cleaned == "", do: "Kiosk", else: cleaned
  end

  defp truncate(value, max) when is_binary(value) do
    if byte_size(value) <= max, do: value, else: binary_part(value, 0, max)
  end

  defp parse_amount(nil), do: nil

  defp parse_amount(raw) when is_binary(raw) do
    case Decimal.parse(raw) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp text(map, key) when is_map(map) do
    case Map.get(map, key) do
      v when is_binary(v) and v != "" -> v
      v when is_integer(v) -> Integer.to_string(v)
      _ -> nil
    end
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
