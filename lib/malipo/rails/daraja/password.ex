defmodule Malipo.Rails.Daraja.Password do
  @moduledoc """
  Daraja STK password: Base64(shortcode <> passkey <> timestamp).

  One place — push, query, and validate must all use this so whitespace
  normalisation cannot diverge (see Daraja defect register §25.2).
  """

  @spec build(String.t(), String.t(), String.t()) :: String.t()
  def build(shortcode, passkey, timestamp)
      when is_binary(shortcode) and is_binary(passkey) and is_binary(timestamp) do
    sc = shortcode |> String.trim() |> then(&Regex.replace(~r/\s+/, &1, ""))
    pk = passkey |> then(&Regex.replace(~r/\s+/, &1, ""))

    Base.encode64(sc <> pk <> timestamp)
  end

  @spec timestamp(DateTime.t()) :: String.t()
  def timestamp(%DateTime{} = dt) do
    # Africa/Nairobi is UTC+3 year-round (no DST). Avoid a tzdata dependency.
    eat =
      dt
      |> DateTime.to_unix()
      |> Kernel.+(3 * 3600)
      |> DateTime.from_unix!()

    Calendar.strftime(eat, "%Y%m%d%H%M%S")
  end
end
