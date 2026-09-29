defmodule Malipo.Rails.Failure do
  @moduledoc """
  Classified rail failure.

  Daraja conflates "still pending" and "wrong credentials" under ResultCode 4999.
  Callers must never treat a Failure as opaque — use `kind` for retries and UX.
  """

  @enforce_keys [:kind, :message]
  defstruct [:kind, :message, :provider_code, :retryable?, :raw]

  @type kind ::
          :pending
          | :subscriber_cancelled
          | :customer_declined
          | :timeout
          | :customer_timeout
          | :bad_passkey
          | :bad_credentials
          | :insufficient_funds
          | :insufficient_balance
          | :wrong_pin
          | :invalid_amount
          | :invalid_phone
          | :rate_limited
          | :provider_unavailable
          | :inconclusive
          | :unknown

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          provider_code: String.t() | integer() | nil,
          retryable?: boolean() | nil,
          raw: term()
        }

  @spec new(kind(), String.t(), keyword()) :: t()
  def new(kind, message, opts \\ []) when is_atom(kind) and is_binary(message) do
    %__MODULE__{
      kind: kind,
      message: message,
      provider_code: Keyword.get(opts, :provider_code),
      retryable?: Keyword.get(opts, :retryable?),
      raw: Keyword.get(opts, :raw)
    }
  end
end
