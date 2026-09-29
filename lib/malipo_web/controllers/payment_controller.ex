defmodule MalipoWeb.PaymentController do
  @moduledoc "Public merchant payments API — `/v1/payments`."

  use MalipoWeb, :controller

  alias Malipo.Intents
  alias Malipo.Intents.Intent
  alias Malipo.Merchants
  alias Malipo.Rails.Failure

  action_fallback MalipoWeb.FallbackController

  @doc """
  POST /v1/payments

  Optional `callback_url` is where we POST `payment.settled` / `payment.failed`.
  Omit it and poll `GET /v1/payments/:id` instead. No account webhook to register.
  """
  def create(conn, params) do
    business_id = conn.assigns.business_id

    with {:ok, callback} <- take_callback(params["callback_url"]) do
      if Merchants.collections_allowed?(business_id) do
        attrs = public_to_intent(params, business_id, callback)

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

    case Intents.get(id) do
      %Intent{business_id: ^business_id} = intent ->
        json(conn, payment_json(intent))

      %Intent{} ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp public_to_intent(params, business_id, callback) do
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
      "amount" => params["amount"],
      "currency" => params["currency"] || "KES",
      "payer_msisdn" => params["customer_phone"] || params["payer_msisdn"],
      "idempotency_key" => params["idempotency_key"],
      "context" => context
    }
  end

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
