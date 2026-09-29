defmodule MalipoWeb.TillAwaitController do
  @moduledoc """
  Buy Goods await windows — open a listen slot, no STK (§7.2).
  """

  use MalipoWeb, :controller

  alias Malipo.Intents
  alias Malipo.Intents.Intent

  action_fallback MalipoWeb.FallbackController

  @doc "POST /internal/v1/till-awaits"
  def create(conn, params) do
    case Intents.open_till_await(params) do
      {:ok, %Intent{} = intent, :replay} ->
        conn
        |> put_status(:ok)
        |> put_view(json: MalipoWeb.IntentJSON)
        |> render(:show, intent: intent, replay: true)

      {:ok, %Intent{} = intent} ->
        conn
        |> put_status(:created)
        |> put_view(json: MalipoWeb.IntentJSON)
        |> render(:show, intent: intent, replay: false)

      {:error, :invalid_amount} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: MalipoWeb.IntentJSON)
        |> render(:error, error: :invalid_amount)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
