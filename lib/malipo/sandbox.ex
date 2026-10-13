defmodule Malipo.Sandbox do
  @moduledoc """
  KioskPay sandbox (test mode) — simulated payments.

  An intent created with a `test` key never touches Safaricom and never moves
  money. Its outcome is deterministic, in three layers:

    * a **reserved number** (`2540…`) settles or fails immediately,
    * any **other number** settles automatically a few seconds later,
    * `simulate/3` forces a terminal state on demand (the CI path).

  Settlements carry a synthetic `TEST…` receipt (namespaced so it can never
  collide with a real M-Pesa receipt), and `Intents` writes no outbox event and
  no fee for a test intent — so nothing here can reach the monolith.
  """

  alias Malipo.Intents
  alias Malipo.Intents.Intent

  # Unallocated range: a test payment can never ring a real person.
  @reserved_re ~r/^2540\d{8}$/

  @outcomes %{
    "254000000001" => :settled,
    "254000000002" => {:failed, "insufficient_funds"},
    "254000000003" => {:failed, "wrong_pin"},
    "254000000004" => {:failed, "customer_timeout"},
    "254000000005" => {:failed, "subscriber_cancelled"}
  }

  @failure_kinds ~w(
    customer_declined subscriber_cancelled customer_timeout timeout
    insufficient_funds wrong_pin expired
  )

  @auto_settle_seconds 5

  @doc "Reserved sandbox numbers and their outcomes (kept in sync with the guide)."
  @spec outcomes() :: map()
  def outcomes, do: @outcomes

  @doc "Allowed `failure_kind` values for `simulate/3`."
  @spec failure_kinds() :: [String.t()]
  def failure_kinds, do: @failure_kinds

  @doc "True when `msisdn` is a reserved sandbox number."
  @spec reserved?(String.t() | nil) :: boolean()
  def reserved?(msisdn) when is_binary(msisdn), do: Regex.match?(@reserved_re, msisdn)
  def reserved?(_), do: false

  @doc "Normalise a reserved sandbox number (digits only), or `:error`."
  @spec normalise_msisdn(String.t() | nil) :: {:ok, String.t()} | :error
  def normalise_msisdn(raw) when is_binary(raw) do
    digits = Regex.replace(~r/\D/, raw, "")

    if Regex.match?(@reserved_re, digits), do: {:ok, digits}, else: :error
  end

  def normalise_msisdn(_), do: :error

  @doc """
  Simulate the STK prompt for a test intent (called from the push path).

  Reaches `prompted`, then settles/fails immediately for a reserved number, or
  schedules an auto-settle for any other number.
  """
  @spec push(Intent.t(), keyword()) :: {:ok, Intent.t()} | {:error, term()}
  def push(%Intent{} = intent, _opts) do
    with {:ok, prompted} <- Intents.mark_prompted(intent, prompt_attrs(intent)) do
      case Map.get(@outcomes, intent.payer_msisdn, :auto) do
        :settled -> settle(prompted)
        {:failed, kind} -> fail(prompted, kind)
        :auto -> schedule_auto_settle(prompted)
      end
    end
  end

  @doc "Settle a test intent with a synthetic receipt."
  @spec settle(Intent.t()) :: {:ok, Intent.t()} | {:error, term()}
  def settle(%Intent{mode: "test"} = intent) do
    Intents.mark_settled(intent, %{receipt: synthetic_receipt(intent)})
  end

  def settle(%Intent{}), do: {:error, :not_test_intent}

  @doc "Fail a test intent with a classified reason."
  @spec fail(Intent.t(), String.t() | atom()) :: {:ok, Intent.t()} | {:error, term()}
  def fail(%Intent{mode: "test"} = intent, kind) do
    kind = to_string(kind)

    if kind in @failure_kinds do
      Intents.mark_failed(intent, %{
        failure_kind: kind,
        failure_message: failure_message(kind)
      })
    else
      {:error, :invalid_failure_kind}
    end
  end

  def fail(%Intent{}, _kind), do: {:error, :not_test_intent}

  @doc "Force a terminal state — the deterministic CI path."
  @spec simulate(Intent.t(), :settled | :failed, String.t() | nil) ::
          {:ok, Intent.t()}
          | {:error, :invalid_outcome | :invalid_failure_kind | :not_test_intent | term()}
  def simulate(%Intent{} = intent, :settled, _kind), do: settle(intent)
  def simulate(%Intent{} = intent, :failed, kind), do: fail(intent, kind || "customer_declined")
  def simulate(%Intent{}, _outcome, _kind), do: {:error, :invalid_outcome}

  @doc "Synthetic receipt — namespaced so it can never match a real M-Pesa receipt."
  @spec synthetic_receipt(Intent.t()) :: String.t()
  def synthetic_receipt(_intent) do
    seed =
      Ecto.UUID.generate()
      |> String.replace("-", "")
      |> String.slice(0, 10)
      |> String.upcase()

    "TEST" <> seed
  end

  # ── internals ─────────────────────────────────────────────────────

  defp prompt_attrs(intent) do
    seed = intent.id |> String.replace("-", "") |> String.slice(0, 12)

    %{
      checkout_request_id: "ws_CO_test_" <> seed,
      merchant_request_id: "test-" <> seed,
      request_payload: %{"simulated" => true, "mode" => "test"},
      response_payload: %{"simulated" => true, "ResponseCode" => "0"}
    }
  end

  defp schedule_auto_settle(intent) do
    %{intent_id: intent.id}
    |> Malipo.Sandbox.AutoSettle.new(scheduled_in: @auto_settle_seconds)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, intent}
      {:error, _reason} -> {:ok, intent}
    end
  end

  defp failure_message("insufficient_funds"), do: "Customer has insufficient M-Pesa balance"
  defp failure_message("wrong_pin"), do: "Wrong M-Pesa PIN"
  defp failure_message("customer_timeout"), do: "Customer didn't respond — resend"
  defp failure_message("subscriber_cancelled"), do: "Customer cancelled the prompt"
  defp failure_message("customer_declined"), do: "Customer declined the prompt"
  defp failure_message("timeout"), do: "Timed out"
  defp failure_message("expired"), do: "The prompt window closed"
  defp failure_message(_), do: "Simulated failure"
end
