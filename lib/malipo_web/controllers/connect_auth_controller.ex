defmodule MalipoWeb.ConnectAuthController do
  @moduledoc """
  Connect-owned merchant auth — register / login (email + password).
  """

  use MalipoWeb, :controller

  alias Malipo.ConnectAccounts
  alias Malipo.ConnectAccounts.Account

  action_fallback MalipoWeb.FallbackController

  @doc "POST /internal/v1/connect/register"
  def register(conn, params) do
    case ConnectAccounts.register(params) do
      {:ok, %Account{} = account} ->
        conn
        |> put_status(:created)
        |> json(account_json(account))

      {:error, %Ecto.Changeset{} = cs} ->
        {:error, cs}
    end
  end

  @doc "POST /internal/v1/connect/login"
  def login(conn, params) do
    email = params["email"] || ""
    password = params["password"] || ""

    case ConnectAccounts.authenticate(email, password) do
      {:ok, %Account{} = account} ->
        json(conn, account_json(account))

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: MalipoWeb.IntentJSON)
        |> render(:error, error: :invalid_credentials)
    end
  end

  defp account_json(%Account{} = a) do
    %{
      id: a.id,
      email: a.email,
      business_id: a.business_id,
      display_name: a.display_name
    }
  end
end
