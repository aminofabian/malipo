defmodule Malipo.Rails.Registry do
  @moduledoc """
  Resolves a rail atom to its implementation module.

  Only Daraja is registered in this scope.
  """

  alias Malipo.Rails.Daraja

  @rails %{
    daraja: Daraja
  }

  @spec fetch(atom()) :: {:ok, module()} | {:error, :unknown_rail}
  def fetch(rail) when is_atom(rail) do
    case Map.fetch(@rails, rail) do
      {:ok, mod} -> {:ok, mod}
      :error -> {:error, :unknown_rail}
    end
  end

  @spec fetch!(atom()) :: module()
  def fetch!(rail) do
    case fetch(rail) do
      {:ok, mod} -> mod
      {:error, :unknown_rail} -> raise ArgumentError, "unknown rail: #{inspect(rail)}"
    end
  end

  @spec known() :: [atom()]
  def known, do: Map.keys(@rails)
end
