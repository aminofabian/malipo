defmodule MalipoWeb.PaymentController do
  @moduledoc "Public merchant payments API — `/v1/payments`."

  use MalipoWeb, :controller

  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Merchants
  alias Malipo.Merchants.ApiKey
  alias Malipo.Rails.Failure
  alias Malipo.Sandbox

  action_fallback(MalipoWeb.FallbackController)

  @doc """
  POST /v1/payments

  Optional `callback_url` is where we POST `payment.settled` / `payment.failed`.
  When it is omitted, the website URL saved on the merchant's key (Connect →
  Settings) is used. Omit both and poll `GET /v1/payments/:id` instead.
  """
  def create(conn, params) do
    business_id = conn.assigns.business_id
    mode = conn.assigns.mode

    with {:ok, callback} <- resolve_callback(business_id, mode, params["callback_url"]) do
      # A sandbox payment needs no settlement destination; a live one does.
      if mode == "test" or Merchants.collections_allowed?(business_id) do
        attrs = public_to_intent(params, business_id, mode, callback)

        case Intents.create_and_push(attrs) do
          {:ok, %Intent{} = intent, :replay} ->
            conn
            |> put_status(:ok)
            |> json(payment_json(intent))

          {:ok, %Intent{} = intent} ->
            conn
            |> put_status(:created)
            |> json(payment_json(intent))

          {:error, %Failure{} = failure} ->
            {:error, failure, lookup(attrs)}

          {:error, reason} ->
            {:error, reason}
        end
      else
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "destination_inactive",
          message: "Settlement destination is not activated yet"
        })
      end
    end
  end

  @doc "GET /v1/payments/:id"
  def show(conn, %{"id" => id}) do
    business_id = conn.assigns.business_id
    mode = conn.assigns.mode

    case Intents.get(id) do
      %Intent{business_id: ^business_id, mode: ^mode} = intent ->
        json(conn, payment_json(intent))

      %Intent{} ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  POST /v1/payments/:id/simulate — test mode only.

  Forces a terminal state on a sandbox payment, deterministically:
  `{"outcome":"settled"}` or `{"outcome":"failed","failure_kind":"wrong_pin"}`.
  """
  def simulate(conn, %{"id" => id} = params) do
    business_id = conn.assigns.business_id

    with %Intent{business_id: ^business_id, mode: "test"} = intent <- Intents.get(id),
         {:ok, outcome} <- parse_outcome(params["outcome"]),
         {:ok, updated} <- Sandbox.simulate(intent, outcome, params["failure_kind"]) do
      json(conn, payment_json(updated))
    else
      %Intent{} ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}

      {:error, :invalid_outcome} ->
        unprocessable(conn, "invalid_outcome", ~s(outcome must be "settled" or "failed"))

      {:error, :invalid_failure_kind} ->
        unprocessable(conn, "invalid_failure_kind", "unknown failure_kind")

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_outcome("settled"), do: {:ok, :settled}
  defp parse_outcome("failed"), do: {:ok, :failed}
  defp parse_outcome(_), do: {:error, :invalid_outcome}

  defp unprocessable(conn, error, message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: error, message: message})
  end

  defp public_to_intent(params, business_id, mode, callback) do
    ref = params["reference"]

    context =
      (params["context"] || %{})
      |> Map.drop(["callback_url"])
      |> Map.merge(%{"type" => "MERCHANT_API", "reference" => ref})

    context =
      if is_binary(callback) do
        Map.put(context, "callback_url", callback)
      else
        context
      end

    %{
      "business_id" => business_id,
      "mode" => mode,
      "amount" => params["amount"],
      "currency" => params["currency"] || "KES",
      "payer_msisdn" => params["customer_phone"] || params["payer_msisdn"],
      "idempotency_key" => params["idempotency_key"],
      "context" => context
    }
  end

  # A per-request callback_url wins; otherwise fall back to the key's saved
  # website URL (set in Connect → Settings). Not sending either means "poll".
  defp resolve_callback(business_id, mode, nil) do
    case Merchants.get_active_key(business_id, mode) do
      %ApiKey{webhook_url: url} when is_binary(url) -> {:ok, url}
      _ -> {:ok, nil}
    end
  end

  defp resolve_callback(_business_id, _mode, url), do: take_callback(url)

  defp take_callback(nil), do: {:ok, nil}

  defp take_callback(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" -> {:ok, nil}
      Merchants.valid_callback_url?(url) -> {:ok, url}
      true -> {:error, :invalid_callback_url}
    end
  end

  defp take_callback(_), do: {:error, :invalid_callback_url}

  defp payment_json(%Intent{} = intent) do
    status =
      case intent.status do
        "settled" -> "settled"
        "failed" -> "failed"
        "expired" -> "failed"
        _ -> "pending"
      end

    %{
      id: intent.id,
      status: status,
      amount: Decimal.to_string(intent.amount),
      currency: intent.currency,
      reference: get_in(intent.context || %{}, ["reference"]),
      failure_kind: intent.failure_kind,
      failure_message: intent.failure_message,
      receipt: intent.receipt,
      callback_url: get_in(intent.context || %{}, ["callback_url"])
    }
  end

  defp lookup(%{"business_id" => biz, "idempotency_key" => key})
       when is_binary(biz) and is_binary(key) do
    Intents.get_by_idempotency(biz, key)
  end

  defp lookup(_), do: nil
end
