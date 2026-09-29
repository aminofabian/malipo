defmodule MalipoWeb.HealthController do
  @moduledoc "Liveness and readiness probes."

  use MalipoWeb, :controller

  alias Malipo.Health

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Health.ready() do
      {:ok, body} ->
        json(conn, body)

      {:error, body} ->
        conn
        |> put_status(:service_unavailable)
        |> json(body)
    end
  end
end
