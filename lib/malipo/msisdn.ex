defmodule Malipo.Msisdn do
  @moduledoc """
  Normalise Kenyan MSISDNs for Daraja STK.

  Port of the monolith `StkPhoneNormalizer` — one shape only:
  `2547XXXXXXXX` / `2541XXXXXXXX` (12 digits).
  """

  @spec normalise(String.t() | nil) :: {:ok, String.t()} | {:error, :invalid_phone}
  def normalise(nil), do: {:error, :invalid_phone}

  def normalise(raw) when is_binary(raw) do
    digits = Regex.replace(~r/\D/, raw, "")

    cond do
      String.match?(digits, ~r/^254[17]\d{8}$/) ->
        {:ok, digits}

      String.match?(digits, ~r/^0[17]\d{8}$/) ->
        {:ok, "254" <> String.slice(digits, 1, 9)}

      String.match?(digits, ~r/^[17]\d{8}$/) ->
        {:ok, "254" <> digits}

      true ->
        {:error, :invalid_phone}
    end
  end

  @spec normalise!(String.t()) :: String.t()
  def normalise!(raw) do
    case normalise(raw) do
      {:ok, msisdn} -> msisdn
      {:error, :invalid_phone} -> raise ArgumentError, "invalid MSISDN: #{inspect(raw)}"
    end
  end
end
