defmodule Malipo.ConnectAccounts do
  @moduledoc """
  Connect merchant accounts — register and authenticate with email + password.
  """

  import Ecto.Query

  alias Malipo.ConnectAccounts.Account
  alias Malipo.ConnectAccounts.Password
  alias Malipo.Repo

  @doc "Register a new Connect merchant."
  @spec register(map()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def register(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> Account.registration_changeset()
    |> Repo.insert()
  end

  @doc "Authenticate by email + password."
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Account.t()} | {:error, :invalid_credentials}
  def authenticate(email, password)
      when is_binary(email) and is_binary(password) do
    email = email |> String.trim() |> String.downcase()

    case Repo.get_by(Account, email: email) do
      %Account{} = account ->
        if Password.verify(password, account.password_hash) do
          {:ok, account}
        else
          Password.no_user_verify()
          {:error, :invalid_credentials}
        end

      nil ->
        Password.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc "Fetch by business id."
  @spec get_by_business_id(String.t()) :: Account.t() | nil
  def get_by_business_id(business_id) when is_binary(business_id) do
    Repo.get_by(Account, business_id: business_id)
  end

  @doc "Fetch by email."
  @spec get_by_email(String.t()) :: Account.t() | nil
  def get_by_email(email) when is_binary(email) do
    Repo.get_by(Account, email: email |> String.trim() |> String.downcase())
  end

  @doc "Recent accounts for admin."
  @spec list_recent(non_neg_integer()) :: [Account.t()]
  def list_recent(limit \\ 50) do
    from(a in Account, order_by: [desc: a.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
