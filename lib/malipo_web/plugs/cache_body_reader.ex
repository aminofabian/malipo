defmodule MalipoWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Captures the raw request body for webhook routes that must persist bytes
  before any interpretation (Daraja scope §10).
  """

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, remember(conn, body)}

      {:more, partial, conn} ->
        {:more, partial, remember(conn, partial)}

      other ->
        other
    end
  end

  @spec raw_body(Plug.Conn.t()) :: binary()
  def raw_body(conn) do
    conn.assigns
    |> Map.get(:raw_body, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp remember(conn, chunk) when is_binary(chunk) do
    update_in(conn.assigns[:raw_body], &[chunk | &1 || []])
  end
end
