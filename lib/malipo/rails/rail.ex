defmodule Malipo.Rails.Rail do
  @moduledoc """
  Behaviour for a money-movement rail.

  Daraja is the only implementation today. The contract is intentionally rail-agnostic
  so a second provider could plug in without rewriting intents/webhooks/outbox.
  """

  alias Malipo.Rails.Failure

  @type business_id :: String.t()
  @type credentials :: map()
  @type push_request :: %{
          required(:amount) => Decimal.t(),
          required(:phone) => String.t(),
          required(:account_reference) => String.t(),
          required(:transaction_desc) => String.t(),
          optional(:callback_url) => String.t()
        }
  @type push_result :: %{
          checkout_request_id: String.t(),
          merchant_request_id: String.t() | nil,
          raw: map()
        }
  @type query_result :: %{
          optional(:outcome) => :success | :pending | :failed,
          result_code: String.t() | integer() | nil,
          result_desc: String.t() | nil,
          receipt: String.t() | nil,
          amount: Decimal.t() | nil,
          phone: String.t() | nil,
          raw: map()
        }
  @type transfer_request :: %{
          required(:amount) => Decimal.t(),
          required(:destination) => map(),
          required(:result_url) => String.t(),
          required(:timeout_url) => String.t(),
          optional(:account_reference) => String.t(),
          optional(:remarks) => String.t()
        }
  @type transfer_result :: %{
          conversation_id: String.t(),
          originator_conversation_id: String.t() | nil,
          raw: map()
        }

  @callback validate(credentials()) :: :ok | {:error, Failure.t()}
  @callback push(credentials(), push_request()) :: {:ok, push_result()} | {:error, Failure.t()}
  @callback query(credentials(), checkout_request_id :: String.t()) ::
              {:ok, query_result()} | {:error, Failure.t()}

  @doc "Move money rail-to-rail (e.g. a fee sweep). Credentials come from the rail."
  @callback transfer(credentials(), transfer_request()) ::
              {:ok, transfer_result()} | {:error, Failure.t()}
end
