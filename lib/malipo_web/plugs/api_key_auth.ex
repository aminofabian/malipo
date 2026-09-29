defmodule MalipoWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Auth for the public merchant API. Assigns `:business_id` on success.

  * `Authorization: Bearer sk_live_…` — the secret is the whole credential
  * `Authorization: Basic base64(client_id:client_secret)` — still accepted
  """

  @behaviour Plug

  import Plug.Conn

  alias Malipo.Merchants

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case business_id(conn) do
      {:ok, business_id} ->
        assign(conn, :business_id, business_id)

      :error ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="malipo"))
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp business_id(conn) do
    result =
      case get_req_header(conn, "authorization") do
        [header] ->
          case String.split(header, " ", parts: 2) do
            [scheme, credential] ->
              case String.downcase(scheme) do
                "bearer" -> Merchants.authenticate_secret(credential)
                "basic" -> basic(credential)
                _ -> :error
              end

            _ ->
              :error
          end

        _ ->
          :error
      end

    case result do
      {:ok, business_id} -> {:ok, business_id}
      _ -> :error
    end
  end

  defp basic(encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [client_id, client_secret] <- String.split(decoded, ":", parts: 2) do
      Merchants.authenticate(client_id, client_secret)
    else
      _ -> :error
    end
  end
end
