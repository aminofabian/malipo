defmodule Malipo.Merchants do
  @moduledoc """
  Merchant settlement destinations and API keys for Malipo Connect.

  Secrets are write-only: plaintext is returned once from `provision_keys/1`
  and only the SHA-256 hash is stored.
  """

  import Ecto.Query

  alias Malipo.Merchants.{ApiKey, Destination}
  alias Malipo.Repo

  @doc "Fetch destination for a business."
  @spec get_destination(String.t()) :: Destination.t() | nil
  def get_destination(business_id) when is_binary(business_id) do
    Repo.get_by(Destination, business_id: business_id)
  end

  @doc "Upsert a draft destination (not activated until confirm)."
  @spec put_destination(String.t(), map()) ::
          {:ok, Destination.t()} | {:error, Ecto.Changeset.t()}
  def put_destination(business_id, attrs) when is_binary(business_id) and is_map(attrs) do
    attrs =
      attrs
      |> stringify()
      |> Map.put("business_id", business_id)
      |> Map.put("verified", false)
      |> Map.put("activated", false)
      |> maybe_display_name()

    case get_destination(business_id) do
      nil ->
        %Destination{} |> Destination.changeset(attrs) |> Repo.insert()

      %Destination{} = row ->
        row |> Destination.changeset(attrs) |> Repo.update()
    end
  end

  @doc "Mark destination verified + activated after merchant confirms."
  @spec confirm_destination(String.t()) ::
          {:ok, Destination.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def confirm_destination(business_id) when is_binary(business_id) do
    case get_destination(business_id) do
      nil ->
        {:error, :not_found}

      %Destination{} = row ->
        row
        |> Destination.changeset(%{verified: true, activated: true})
        |> Repo.update()
    end
  end

  @doc "True when collections may run for this business."
  @spec collections_allowed?(String.t()) :: boolean()
  def collections_allowed?(business_id) when is_binary(business_id) do
    case get_destination(business_id) do
      %Destination{activated: true, verified: true} -> true
      _ -> false
    end
  end

  @doc """
  Issue (or rotate) API keys. Returns plaintext secrets **once**.

  Revokes any previous active key for the business.
  """
  @spec provision_keys(String.t()) ::
          {:ok, map()} | {:error, :destination_not_ready | Ecto.Changeset.t()}
  def provision_keys(business_id) when is_binary(business_id) do
    case get_destination(business_id) do
      %Destination{verified: true} ->
        client_secret = token("sk_live_")
        webhook_secret = token("whsec_")
        secret_attrs = %{
          client_secret_hash: hash(client_secret),
          webhook_secret_hash: hash(webhook_secret),
          webhook_secret: webhook_secret
        }

        result =
          case get_active_key(business_id) do
            %ApiKey{} = key ->
              key
              |> ApiKey.changeset(secret_attrs)
              |> Repo.update()

            nil ->
              %ApiKey{}
              |> ApiKey.changeset(
                Map.merge(secret_attrs, %{
                  business_id: business_id,
                  client_id: stable_client_id(business_id)
                })
              )
              |> Repo.insert()
          end

        case result do
          {:ok, key} ->
            {:ok,
             %{
               client_id: key.client_id,
               client_secret: client_secret,
               webhook_secret: webhook_secret,
               business_id: business_id
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :destination_not_ready}
    end
  end

  @doc "Authenticate HTTP Basic `client_id:client_secret`. Returns business_id."
  @spec authenticate(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :unauthorized}
  def authenticate(client_id, client_secret)
      when is_binary(client_id) and is_binary(client_secret) do
    case Repo.get_by(ApiKey, client_id: client_id) do
      %ApiKey{} = key -> accept_secret(key, client_secret)
      nil -> {:error, :unauthorized}
    end
  end

  @doc "Authenticate `Authorization: Bearer sk_live_…`. The secret alone identifies the merchant."
  @spec authenticate_secret(String.t()) :: {:ok, String.t()} | {:error, :unauthorized}
  def authenticate_secret(secret) when is_binary(secret) do
    secret = String.trim(secret)

    if secret == "" do
      {:error, :unauthorized}
    else
      case Repo.get_by(ApiKey, client_secret_hash: hash(secret)) do
        %ApiKey{} = key -> accept_secret(key, secret)
        nil -> {:error, :unauthorized}
      end
    end
  end

  defp accept_secret(%ApiKey{} = key, secret) do
    if ApiKey.active?(key) and secure_hash_eq(key.client_secret_hash, secret) do
      {:ok, key.business_id}
    else
      {:error, :unauthorized}
    end
  end

  @doc "Active (non-revoked) key for a business, if any."
  @spec get_active_key(String.t()) :: ApiKey.t() | nil
  def get_active_key(business_id) when is_binary(business_id) do
    from(k in ApiKey,
      where: k.business_id == ^business_id and is_nil(k.revoked_at),
      order_by: [desc: k.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Recent destinations newest-first (ops console)."
  @spec list_destinations(non_neg_integer()) :: [Destination.t()]
  def list_destinations(limit \\ 50) do
    from(d in Destination,
      order_by: [desc: d.updated_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "Set or replace the merchant webhook URL on the active key."
  @spec set_webhook_url(String.t(), String.t() | nil) ::
          {:ok, ApiKey.t()} | {:error, :no_active_key | :invalid_url | Ecto.Changeset.t()}
  def set_webhook_url(business_id, url) when is_binary(business_id) do
    url = url && String.trim(url)

    cond do
      is_nil(url) or url == "" ->
        do_set_webhook(business_id, nil)

      not valid_callback_url?(url) ->
        {:error, :invalid_url}

      true ->
        do_set_webhook(business_id, url)
    end
  end

  defp do_set_webhook(business_id, url) do
    case get_active_key(business_id) do
      nil ->
        {:error, :no_active_key}

      %ApiKey{} = key ->
        key |> ApiKey.changeset(%{webhook_url: url}) |> Repo.update()
    end
  end

  @doc """
  Callback target: `https` with a host, or `http` on localhost / 127.0.0.1.
  """
  @spec valid_callback_url?(String.t()) :: boolean()
  def valid_callback_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      %URI{scheme: "http", host: "localhost"} -> true
      %URI{scheme: "http", host: "127.0.0.1"} -> true
      _ -> false
    end
  end

  defp stable_client_id(business_id) do
    case get_active_key(business_id) || latest_key(business_id) do
      %ApiKey{client_id: id} -> id
      nil -> token("pk_live_")
    end
  end

  defp latest_key(business_id) do
    from(k in ApiKey,
      where: k.business_id == ^business_id,
      order_by: [desc: k.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp maybe_display_name(%{"display_name" => name} = attrs)
       when is_binary(name) and name != "",
       do: attrs

  defp maybe_display_name(%{"kind" => "till", "till_number" => till} = attrs)
       when is_binary(till) do
    Map.put(attrs, "display_name", "BUSINESS " <> String.slice(till, -3, 3))
  end

  defp maybe_display_name(%{"kind" => "paybill", "paybill_number" => pb} = attrs)
       when is_binary(pb) do
    Map.put(attrs, "display_name", "BUSINESS " <> String.slice(pb, -3, 3))
  end

  defp maybe_display_name(%{"kind" => "bank", "paybill_number" => pb, "account_number" => acc} = attrs)
       when is_binary(pb) and is_binary(acc) do
    Map.put(attrs, "display_name", "Bank paybill #{pb} · Acc #{acc}")
  end

  defp maybe_display_name(attrs), do: attrs

  defp token(prefix) do
    prefix <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp hash(secret) when is_binary(secret) do
    :crypto.hash(:sha256, secret)
  end

  defp secure_hash_eq(stored, secret) when is_binary(stored) and is_binary(secret) do
    Plug.Crypto.secure_compare(stored, hash(secret))
  end

  defp stringify(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end
end
