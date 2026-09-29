defmodule MalipoWeb.MerchantController do
  @moduledoc "Internal merchant provisioning — Connect → Malipo."

  use MalipoWeb, :controller

  alias Malipo.Merchants
  alias Malipo.Merchants.Destination

  action_fallback MalipoWeb.FallbackController

  @doc "PUT /internal/v1/merchants/:business_id/destination"
  def put_destination(conn, %{"business_id" => business_id} = params) do
    attrs = Map.drop(params, ["business_id"])

    case Merchants.put_destination(business_id, attrs) do
      {:ok, %Destination{} = dest} ->
        json(conn, destination_json(dest))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "POST /internal/v1/merchants/:business_id/confirm"
  def confirm(conn, %{"business_id" => business_id}) do
    case Merchants.confirm_destination(business_id) do
      {:ok, %Destination{} = dest} ->
        json(conn, destination_json(dest))

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "POST /internal/v1/merchants/:business_id/keys — secrets returned once."
  def provision_keys(conn, %{"business_id" => business_id}) do
    case Merchants.provision_keys(business_id) do
      {:ok, revealed} ->
        conn
        |> put_status(:created)
        |> json(%{
          client_id: revealed.client_id,
          client_secret: revealed.client_secret,
          webhook_secret: revealed.webhook_secret,
          business_id: revealed.business_id
        })

      {:error, :destination_not_ready} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "destination_not_ready",
          message: "Confirm a settlement destination before issuing keys"
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "PUT /internal/v1/merchants/:business_id/webhook"
  def put_webhook(conn, %{"business_id" => business_id} = params) do
    url = params["url"] || params["webhook_url"]

    case Merchants.set_webhook_url(business_id, url) do
      {:ok, key} ->
        json(conn, %{business_id: business_id, webhook_url: key.webhook_url})

      {:error, :no_active_key} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "no_active_key", message: "Provision keys first"})

      {:error, :invalid_url} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_url", message: "Use an https URL (http ok for localhost)"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "GET /internal/v1/merchants/:business_id"
  def show(conn, %{"business_id" => business_id}) do
    dest = Merchants.get_destination(business_id)
    key = Merchants.get_active_key(business_id)

    json(conn, %{
      business_id: business_id,
      destination: if(dest, do: destination_json(dest), else: nil),
      client_id: key && key.client_id,
      webhook_url: key && key.webhook_url,
      collections_allowed: Merchants.collections_allowed?(business_id)
    })
  end

  @doc "GET /internal/v1/merchants/:business_id/payments — last few intents."
  def payments(conn, %{"business_id" => business_id} = params) do
    limit =
      case Integer.parse(to_string(params["limit"] || "5")) do
        {n, _} when n > 0 and n <= 20 -> n
        _ -> 5
      end

    rows =
      business_id
      |> Malipo.Intents.list_for_business(limit)
      |> Enum.map(&payment_summary/1)

    json(conn, %{business_id: business_id, payments: rows})
  end

  defp payment_summary(%Malipo.Intents.Intent{} = i) do
    %{
      id: i.id,
      status: i.status,
      amount: Decimal.to_string(i.amount),
      currency: i.currency,
      reference: get_in(i.context || %{}, ["reference"]),
      failure_kind: i.failure_kind,
      inserted_at: i.inserted_at && DateTime.to_iso8601(i.inserted_at)
    }
  end

  defp destination_json(%Destination{} = d) do
    %{
      kind: d.kind,
      till_number: d.till_number,
      paybill_number: d.paybill_number,
      account_number: d.account_number,
      bank_id: d.bank_id,
      display_name: d.display_name,
      verified: d.verified,
      activated: d.activated
    }
  end
end
