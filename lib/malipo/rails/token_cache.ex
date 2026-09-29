defmodule Malipo.Rails.TokenCache do
  @moduledoc """
  Per-credential OAuth token cache.

  Keys are `{consumer_key, base_url}`. Tokens refresh ~60s before expiry so
  concurrent STK calls do not stampede Safaricom's `/oauth/v1/generate`.
  """

  use GenServer

  @type cache_key :: {String.t(), String.t()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc "Return a cached token if still valid."
  @spec get(cache_key()) :: String.t() | nil
  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  @doc "Store a token with absolute expiry (unix ms)."
  @spec put(cache_key(), String.t(), non_neg_integer()) :: :ok
  def put(key, token, expires_at_ms),
    do: GenServer.call(__MODULE__, {:put, key, token, expires_at_ms})

  @doc "Drop a cached token (e.g. after 401)."
  @spec invalidate(cache_key()) :: :ok
  def invalidate(key), do: GenServer.call(__MODULE__, {:invalidate, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.system_time(:millisecond)

    reply =
      case Map.get(state, key) do
        %{token: token, expires_at_ms: exp} when exp > now -> token
        _ -> nil
      end

    {:reply, reply, state}
  end

  def handle_call({:put, key, token, expires_at_ms}, _from, state) do
    {:reply, :ok, Map.put(state, key, %{token: token, expires_at_ms: expires_at_ms})}
  end

  def handle_call({:invalidate, key}, _from, state) do
    {:reply, :ok, Map.delete(state, key)}
  end
end
