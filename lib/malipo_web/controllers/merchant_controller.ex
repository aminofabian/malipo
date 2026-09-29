defmodule MalipoWeb.MerchantController do
  @moduledoc "Internal merchant provisioning — Connect → Malipo."

  use MalipoWeb, :controller

  import Ecto.Query

  alias Malipo.Intents.Intent
  alias Malipo.Merchants
  alias Malipo.Merchants.Destination
  alias Malipo.Repo

  action_fallback MalipoWeb.FallbackController

  @doc "PUT /internal/v1/merchants/:business_id/destination — saves a new row."
  def put_destination(conn, %{"business_id" => business_id} = params) do
    attrs = Map.drop(params, ["business_id"])

    case Merchants.create_destination(business_id, attrs) do
      {:ok, %Destination{} = dest} ->
        conn |> put_status(:created) |> json(destination_json(dest))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "POST /internal/v1/merchants/:business_id/destinations"
  def create_destination(conn, params) do
    put_destination(conn, params)
  end

  @doc "GET /internal/v1/merchants/:business_id/destinations"
  def list_destinations(conn, %{"business_id" => business_id}) do
    rows = Merchants.list_for_business(business_id)

    json(conn, %{
      business_id: business_id,
      destinations: Enum.map(rows, &destination_json/1),
      active_destination_id: active_id(rows)
    })
  end

  @doc "GET /internal/v1/merchants/:business_id/destinations/:destination_id"
  def show_destination(conn, %{"business_id" => business_id, "destination_id" => id}) do
    case Merchants.get_destination(business_id, id) do
      %Destination{} = dest -> json(conn, destination_json(dest))
      nil -> {:error, :not_found}
    end
  end

  @doc "POST /internal/v1/merchants/:business_id/confirm"
  def confirm(conn, %{"business_id" => business_id} = params) do
    dest_id = params["destination_id"] || params["id"]
    do_confirm(conn, business_id, dest_id)
  end

  @doc "POST /internal/v1/merchants/:business_id/destinations/:destination_id/confirm"
  def confirm_destination(conn, %{
        "business_id" => business_id,
        "destination_id" => dest_id
      }) do
    do_confirm(conn, business_id, dest_id)
  end

  @doc "POST /internal/v1/merchants/:business_id/destinations/:destination_id/activate"
  def activate_destination(conn, %{
        "business_id" => business_id,
        "destination_id" => dest_id
      }) do
    case Merchants.activate_destination(business_id, dest_id) do
      {:ok, %Destination{} = dest} ->
        json(conn, destination_json(dest))

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :not_verified} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "destination_not_verified",
          message: "Confirm this destination before using it for collections"
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_confirm(conn, business_id, dest_id) do
    case Merchants.confirm_destination(business_id, dest_id) do
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
    dest = Merchants.get_active_destination(business_id)
    key = Merchants.get_active_key(business_id)

    json(conn, %{
      business_id: business_id,
      destination: if(dest, do: destination_json(dest), else: nil),
      destinations_count: Merchants.list_for_business(business_id) |> length(),
      client_id: key && key.client_id,
      webhook_url: key && key.webhook_url,
      collections_allowed: Merchants.collections_allowed?(business_id)
    })
  end

  @doc "GET /internal/v1/merchants/:business_id/summary — settled totals by destination."
  def summary(conn, %{"business_id" => business_id}) do
    grouped =
      from(i in Intent,
        where: i.business_id == ^business_id and i.status == "settled",
        group_by: fragment("?->>'settlement_destination_id'", i.context),
        select:
          {fragment("?->>'settlement_destination_id'", i.context), count(i.id), sum(i.amount)}
      )
      |> Repo.all()

    totals =
      from(i in Intent,
        where: i.business_id == ^business_id and i.status == "settled",
        select: %{count: count(i.id), total: sum(i.amount)}
      )
      |> Repo.one()

    json(conn, %{
      business_id: business_id,
      received_count: totals.count,
      received_total: decimal_str(totals.total),
      by_destination:
        Enum.map(grouped, fn {destination_id, count, total} ->
          %{destination_id: destination_id, count: count, total: decimal_str(total)}
        end)
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

  defp decimal_str(nil), do: "0"
  defp decimal_str(%Decimal{} = d), do: Decimal.to_string(d)

  defp payment_summary(%Malipo.Intents.Intent{} = i) do
    %{
      id: i.id,
      status: i.status,
      amount: Decimal.to_string(i.amount),
      currency: i.currency,
      reference: get_in(i.context || %{}, ["reference"]),
      destination_id: get_in(i.context || %{}, ["settlement_destination_id"]),
      failure_kind: i.failure_kind,
      inserted_at: i.inserted_at && DateTime.to_iso8601(i.inserted_at)
    }
  end

  defp destination_json(%Destination{} = d) do
    %{
      id: d.id,
      kind: d.kind,
      till_number: d.till_number,
      paybill_number: d.paybill_number,
      account_number: d.account_number,
      bank_id: d.bank_id,
      display_name: d.display_name,
      verified: d.verified,
      activated: d.activated,
      active: d.active,
      in_use: d.active,
      inserted_at: d.inserted_at && DateTime.to_iso8601(d.inserted_at)
    }
  end

  defp active_id(rows) do
    case Enum.find(rows, & &1.active) do
      %Destination{id: id} -> id
      nil -> nil
    end
  end
end
