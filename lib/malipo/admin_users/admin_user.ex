defmodule Malipo.AdminUsers.AdminUser do
  @moduledoc """
  A super-admin console operator — email + password, optional name/role.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @roles ~w(admin owner)

  schema "admin_users" do
    field :email, :string
    field :name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :role, :string, default: "admin"
    field :active, :boolean, default: true
    field :last_login_at, :utc_datetime_usec

    timestamps()
  end

  @type t :: %__MODULE__{}

  def roles, do: @roles

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :name, :password, :role, :active])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:password, min: 8, max: 72)
    |> validate_length(:name, max: 191)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  @doc "Change an existing operator's password."
  def password_changeset(%__MODULE__{} = user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> put_password_hash()
  end

  @doc "Change name, role, or active flag."
  def update_changeset(%__MODULE__{} = user, attrs) do
    user
    |> cast(attrs, [:name, :role, :active])
    |> validate_length(:name, max: 191)
    |> validate_inclusion(:role, @roles)
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = cs) do
    put_change(cs, :password_hash, Malipo.Password.hash(password))
  end

  defp put_password_hash(cs), do: cs
end
