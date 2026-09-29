defmodule MalipoWeb.FallbackController do
  @moduledoc "Maps domain errors to JSON responses for internal APIs."

  use MalipoWeb, :controller

  alias Malipo.Rails.Failure

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :not_found)
  end

  def call(conn, {:error, :credentials_missing}) do
    conn
    |> put_status(:service_unavailable)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :credentials_missing)
  end

  def call(conn, {:error, :invalid_phone}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :invalid_phone)
  end

  def call(conn, {:error, :invalid_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :invalid_amount)
  end

  def call(conn, {:error, :invalid_callback_url}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :invalid_callback_url)
  end

  def call(conn, {:error, :destination_inactive}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :destination_inactive)
  end

  def call(conn, {:error, :destination_invalid}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :destination_invalid)
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: :invalid_credentials)
  end

  def call(conn, {:error, {:invalid_status, _} = reason}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: reason)
  end

  def call(conn, {:error, %Failure{} = failure, intent}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: failure, intent: intent)
  end

  def call(conn, {:error, %Failure{} = failure}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: failure)
  end

  def call(conn, {:error, %Ecto.Changeset{} = cs}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: cs)
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: MalipoWeb.IntentJSON)
    |> render(:error, error: reason)
  end
end
