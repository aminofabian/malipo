defmodule Malipo.Rails.Daraja.Client do
  @moduledoc """
  Low-level Finch HTTP client for Daraja OAuth + STK endpoints.
  """

  alias Malipo.Rails.Daraja.Credentials
  alias Malipo.Rails.Failure
  alias Malipo.Rails.TokenCache

  @oauth_path "/oauth/v1/generate?grant_type=client_credentials"
  @stk_push_path "/mpesa/stkpush/v1/processrequest"
  @stk_query_path "/mpesa/stkpushquery/v1/query"
  @transfer_path "/mpesa/b2b/v1/paymentrequest"

  @receive_timeout 15_000

  @spec oauth_token(Credentials.t()) :: {:ok, String.t()} | {:error, Failure.t()}
  def oauth_token(%{consumer_key: key, consumer_secret: secret, base_url: base} = _creds) do
    cache_key = {key, base}

    case TokenCache.get(cache_key) do
      token when is_binary(token) ->
        {:ok, token}

      nil ->
        fetch_oauth(cache_key, key, secret, base)
    end
  end

  @spec stk_push(Credentials.t(), map()) :: {:ok, map()} | {:error, Failure.t()}
  def stk_push(creds, body) when is_map(body) do
    with {:ok, token} <- oauth_token(creds) do
      post_json(creds.base_url <> @stk_push_path, token, body)
    end
  end

  @spec stk_query(Credentials.t(), map()) :: {:ok, map()} | {:error, Failure.t()}
  def stk_query(creds, body) when is_map(body) do
    with {:ok, token} <- oauth_token(creds) do
      post_json(creds.base_url <> @stk_query_path, token, body)
    end
  end

  @spec transfer(Credentials.t(), map()) :: {:ok, map()} | {:error, Failure.t()}
  def transfer(creds, body) when is_map(body) do
    with {:ok, token} <- oauth_token(creds) do
      post_json(creds.base_url <> @transfer_path, token, body)
    end
  end

  defp fetch_oauth(cache_key, key, secret, base) do
    basic = Base.encode64(key <> ":" <> secret)
    url = base <> @oauth_path

    request =
      Finch.build(:get, url, [
        {"authorization", "Basic " <> basic},
        {"accept", "application/json"}
      ])

    case Finch.request(request, Malipo.Finch, receive_timeout: @receive_timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token} = root} when is_binary(token) and token != "" ->
            expires_in =
              case Map.get(root, "expires_in") do
                n when is_integer(n) -> n
                s when is_binary(s) -> String.to_integer(s)
                _ -> 3599
              end

            expires_at = System.system_time(:millisecond) + max(expires_in - 60, 30) * 1000
            TokenCache.put(cache_key, token, expires_at)
            {:ok, token}

          _ ->
            {:error,
             Failure.new(:bad_credentials, "Daraja OAuth response missing access_token",
               retryable?: false,
               raw: body
             )}
        end

      {:ok, %{status: status, body: body}} ->
        {:error,
         Failure.new(:bad_credentials, "Daraja OAuth failed HTTP #{status}",
           retryable?: status >= 500,
           provider_code: status,
           raw: clip(body)
         )}

      {:error, reason} ->
        {:error,
         Failure.new(
           :provider_unavailable,
           "Daraja OAuth network error: #{Exception.message(reason)}",
           retryable?: true,
           raw: reason
         )}
    end
  end

  defp post_json(url, token, body) do
    request =
      Finch.build(
        :post,
        url,
        [
          {"authorization", "Bearer " <> token},
          {"content-type", "application/json"},
          {"accept", "application/json"}
        ],
        Jason.encode!(body)
      )

    case Finch.request(request, Malipo.Finch, receive_timeout: @receive_timeout) do
      {:ok, %{status: status, body: raw}} ->
        decoded =
          case Jason.decode(raw || "") do
            {:ok, map} when is_map(map) -> map
            _ -> %{"_raw" => raw, "_status" => status}
          end

        {:ok, Map.put(decoded, "_http_status", status)}

      {:error, reason} ->
        {:error,
         Failure.new(:provider_unavailable, "Daraja network error: #{Exception.message(reason)}",
           retryable?: true,
           raw: reason
         )}
    end
  end

  defp clip(nil), do: nil

  defp clip(body) when is_binary(body) and byte_size(body) > 400,
    do: binary_part(body, 0, 400) <> "…"

  defp clip(body), do: body
end
