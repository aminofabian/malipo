defmodule MalipoWeb.IntentController do
  @moduledoc """
  Internal intent API — Java → Malipo (§7.2).
  """

  use MalipoWeb, :controller

  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Rails.Daraja.Platform
  alias Malipo.Rails.Failure

  action_fallback MalipoWeb.FallbackController

  @doc "POST /internal/v1/intents — create + push."
  def create(conn, params) do
    case Intents.create_and_push(params) do
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

      {:error, %Failure{} = failure} ->
        intent = lookup_from_params(params)
        {:error, failure, intent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "GET /internal/v1/intents/:id"
  def show(conn, %{"id" => id}) do
    case Intents.get(id) do
      %Intent{} = intent ->
        conn
        |> put_view(json: MalipoWeb.IntentJSON)
        |> render(:show, intent: intent, replay: false)

      nil ->
        {:error, :not_found}
    end
  end

  @doc "POST /internal/v1/intents/:id/resend"
  def resend(conn, %{"id" => id}) do
    with %Intent{} = intent <- Intents.get(id) || :not_found,
         creds when is_map(creds) <- Platform.credentials() || :credentials_missing,
         {:ok, %Intent{} = prompted} <- Intents.resend_stk(intent, creds) do
      conn
      |> put_view(json: MalipoWeb.IntentJSON)
      |> render(:show, intent: prompted, replay: false)
    else
      :not_found ->
        {:error, :not_found}

      :credentials_missing ->
        {:error, :credentials_missing}

      {:error, %Failure{} = failure} ->
        {:error, failure, Intents.get(id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lookup_from_params(%{"business_id" => biz, "idempotency_key" => key})
       when is_binary(biz) and is_binary(key) do
    Intents.get_by_idempotency(biz, key)
  end

  defp lookup_from_params(_), do: nil
end
