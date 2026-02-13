Mox.defmock(SoundForge.Spotify.MockClient, for: SoundForge.Spotify.Client)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(SoundForge.Repo, :manual)
