defmodule MalipoWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Auth for the public merchant API. On success assigns `:business_id` and `:mode`.

  * `Authorization: Bearer sk_live_…` — the secret is the whole credential
  * `Authorization: Basic base64(client_id:client_secret)` — still accepted

  Options:

    * `:allow` — the key modes this endpoint accepts (default `["live"]`).

  The default is deliberately live-only: a test key cannot reach any endpoint
  that has not explicitly opted in to `"test"` (sandbox rule 1). A caller whose
  key mode is not allowed gets `403 mode_not_allowed`, never a silent downgrade.
  """

  @behaviour Plug

  import Plug.Conn

  alias Malipo.Merchants

  @default_allow ["live"]

  @impl true
  def init(opts) do
    %{allow: List.wrap(Keyword.get(opts, :allow, @default_allow))}
  end

  @impl true
  def call(conn, %{allow: allow}) do
    case principal(conn) do
      {:ok, %{business_id: business_id, mode: mode}} ->
        if mode in allow do
          conn
          |> assign(:business_id, business_id)
          |> assign(:mode, mode)
        else
          reject(conn, mode, allow)
        end

      :error ->
        unauthorized(conn)
    end
  end

  defp principal(conn) do
    result =
      case get_req_header(conn, "authorization") do
        [header] ->
          case String.split(header, " ", parts: 2) do
            [scheme, credential] ->
              case String.downcase(scheme) do
                "bearer" -> Merchants.principal_by_secret(credential)
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
      {:ok, principal} -> {:ok, principal}
      _ -> :error
    end
  end

  defp basic(encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [client_id, client_secret] <- String.split(decoded, ":", parts: 2) do
      Merchants.principal_by_pair(client_id, client_secret)
    else
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer realm="malipo"))
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end

  defp reject(conn, mode, allow) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      Jason.encode!(%{
        error: "mode_not_allowed",
        key_mode: mode,
        message: reject_message(mode, allow)
      })
    )
    |> halt()
  end

  defp reject_message("test", allow) do
    if "live" in allow do
      "This is a test key; test mode is not enabled on this endpoint."
    else
      "This key cannot be used on this endpoint."
    end
  end

  defp reject_message(_live, _allow), do: "This endpoint accepts test keys only."
end
