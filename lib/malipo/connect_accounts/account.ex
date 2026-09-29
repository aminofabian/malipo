defmodule Malipo.ConnectAccounts.Account do
  @moduledoc """
  Merchant login for Malipo Connect — email + password, own business_id.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "connect_accounts" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :business_id, :string
    field :display_name, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :password, :display_name, :business_id])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:password, min: 8, max: 72)
    |> validate_length(:display_name, max: 191)
    |> put_business_id()
    |> unique_constraint(:email)
    |> unique_constraint(:business_id)
    |> hash_password()
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  defp put_business_id(cs) do
    case get_change(cs, :business_id) do
      id when is_binary(id) and id != "" ->
        cs

      _ ->
        put_change(cs, :business_id, "biz_" <> short_id())
    end
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = cs) do
    put_change(cs, :password_hash, Malipo.ConnectAccounts.Password.hash(password))
  end

  defp hash_password(cs), do: cs

  defp short_id do
    Ecto.UUID.generate() |> String.replace("-", "") |> String.slice(0, 12)
  end
end
