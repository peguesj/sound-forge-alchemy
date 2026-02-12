defmodule SoundForge.Repo do
  use Ecto.Repo,
    otp_app: :sound_forge,
    adapter: Ecto.Adapters.Postgres
end
