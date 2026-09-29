defmodule Malipo.Repo do
  use Ecto.Repo,
    otp_app: :malipo,
    adapter: Ecto.Adapters.Postgres
end
