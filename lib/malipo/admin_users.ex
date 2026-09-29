defmodule Malipo.AdminUsers do
  @moduledoc """
  Super-admin console operators — DB-backed accounts with email + password.

  These sit alongside the environment's break-glass credentials
  (`MALIPO_ADMIN_USER` / `MALIPO_ADMIN_PASSWORD`, see `Malipo.AdminAuth`): the
  env credentials can always sign in, and can be used to create the first DB
  operator on `/admin/team`.
  """

  import Ecto.Query

  alias Malipo.AdminUsers.AdminUser
  alias Malipo.Password
  alias Malipo.Repo

  @doc "Create a new operator. Returns the row or a changeset error."
  @spec create(map()) :: {:ok, AdminUser.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> AdminUser.create_changeset()
    |> Repo.insert()
  end

  @doc "Authenticate an active operator by email + password, stamping last login."
  @spec authenticate(term(), term()) ::
          {:ok, AdminUser.t()} | {:error, :invalid_credentials}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    case get_by_email(email) do
      %AdminUser{active: true} = user ->
        if Password.verify(password, user.password_hash) do
          {:ok, touch_last_login(user)}
        else
          Password.no_user_verify()
          {:error, :invalid_credentials}
        end

      _ ->
        Password.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_email, _password) do
    Password.no_user_verify()
    {:error, :invalid_credentials}
  end

  @doc "Fetch an operator by id."
  @spec get(Ecto.UUID.t()) :: AdminUser.t() | nil
  def get(id) when is_binary(id), do: Repo.get(AdminUser, id)

  @doc "Fetch an operator by email (case-insensitive)."
  @spec get_by_email(String.t()) :: AdminUser.t() | nil
  def get_by_email(email) when is_binary(email) do
    Repo.get_by(AdminUser, email: email |> String.trim() |> String.downcase())
  end

  @doc "All operators, newest first."
  @spec list(non_neg_integer()) :: [AdminUser.t()]
  def list(limit \\ 100) do
    from(u in AdminUser, order_by: [desc: u.inserted_at], limit: ^limit) |> Repo.all()
  end

  @doc "Number of operators (any state)."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(AdminUser, :count, :id)

  @doc "True when at least one active operator can sign in."
  @spec any_active?() :: boolean()
  def any_active? do
    from(u in AdminUser, where: u.active == true, limit: 1) |> Repo.exists?()
  end

  @doc "Change an operator's password."
  @spec update_password(AdminUser.t(), map()) ::
          {:ok, AdminUser.t()} | {:error, Ecto.Changeset.t()}
  def update_password(%AdminUser{} = user, attrs) do
    user |> AdminUser.password_changeset(attrs) |> Repo.update()
  end

  @doc "Change name, role, or active flag."
  @spec update_operator(AdminUser.t(), map()) ::
          {:ok, AdminUser.t()} | {:error, Ecto.Changeset.t()}
  def update_operator(%AdminUser{} = user, attrs) do
    user |> AdminUser.update_changeset(attrs) |> Repo.update()
  end

  @doc "Enable or disable an operator."
  @spec set_active(AdminUser.t(), boolean()) ::
          {:ok, AdminUser.t()} | {:error, Ecto.Changeset.t()}
  def set_active(%AdminUser{} = user, active) when is_boolean(active) do
    update_operator(user, %{active: active})
  end

  defp touch_last_login(%AdminUser{} = user) do
    user
    |> Ecto.Changeset.change(last_login_at: DateTime.utc_now())
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, _} -> user
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
