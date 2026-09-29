defmodule MalipoWeb.IntentJSON do
  @moduledoc false

  alias Malipo.Intents.Intent
  alias Malipo.Rails.Failure

  def show(%{intent: intent} = assigns) do
    data(intent, Map.get(assigns, :replay, false))
  end

  def error(%{error: :credentials_missing}) do
    %{error: "credentials_missing", message: "Platform Daraja credentials are not configured"}
  end

  def error(%{error: :invalid_phone}) do
    %{error: "invalid_phone", message: "payer_msisdn is not a valid Kenyan MSISDN"}
  end

  def error(%{error: :invalid_amount}) do
    %{error: "invalid_amount", message: "amount must be a positive number"}
  end

  def error(%{error: :invalid_callback_url}) do
    %{error: "invalid_callback_url", message: "callback_url must be an https URL"}
  end

  def error(%{error: :destination_inactive}) do
    %{
      error: "destination_inactive",
      message: "Confirm a till, paybill, or bank in Connect before collecting"
    }
  end

  def error(%{error: :destination_invalid}) do
    %{
      error: "destination_invalid",
      message: "Settlement destination is incomplete or invalid"
    }
  end

  def error(%{error: :invalid_credentials}) do
    %{error: "invalid_credentials", message: "Email or password is incorrect"}
  end

  def error(%{error: :not_found}) do
    %{error: "not_found", message: "Intent not found"}
  end

  def error(%{error: {:invalid_status, status}}) do
    %{error: "invalid_status", message: "Cannot perform this action from status #{status}"}
  end

  def error(%{error: %Failure{} = failure, intent: intent}) do
    %{
      error: "rail_failure",
      kind: failure.kind,
      message: failure.message,
      provider_code: failure.provider_code,
      intent: data(intent, false)
    }
  end

  def error(%{error: %Failure{} = failure}) do
    %{
      error: "rail_failure",
      kind: failure.kind,
      message: failure.message,
      provider_code: failure.provider_code
    }
  end

  def error(%{error: %Ecto.Changeset{} = cs}) do
    %{
      error: "invalid",
      details:
        Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  def error(%{error: reason}) do
    %{error: "error", message: inspect(reason)}
  end

  def not_implemented(%{feature: feature}) do
    %{error: "not_implemented", message: "#{feature} is not available yet"}
  end

  defp data(%Intent{} = intent, replay) do
    %{
      id: intent.id,
      status: intent.status,
      business_id: intent.business_id,
      idempotency_key: intent.idempotency_key,
      amount: Decimal.to_string(intent.amount),
      currency: intent.currency,
      payer_msisdn: intent.payer_msisdn,
      rail: intent.rail,
      context: intent.context || %{},
      checkout_request_id: intent.checkout_request_id,
      merchant_request_id: intent.merchant_request_id,
      receipt: intent.receipt,
      failure_kind: intent.failure_kind,
      failure_message: intent.failure_message,
      failure_provider_code: intent.failure_provider_code,
      expires_at: dt(intent.expires_at),
      prompted_at: dt(intent.prompted_at),
      settled_at: dt(intent.settled_at),
      failed_at: dt(intent.failed_at),
      expired_at: dt(intent.expired_at),
      replay: replay
    }
  end

  defp dt(nil), do: nil
  defp dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
