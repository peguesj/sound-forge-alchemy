# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sound_forge, :scopes,
  user: [
    default: true,
    module: SoundForge.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: SoundForge.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :sound_forge,
  ecto_repos: [SoundForge.Repo],
  generators: [timestamp_type: :utc_datetime],
  max_upload_size: 100_000_000,
  tracks_per_page: 24,
  download_quality: "320k",
  analysis_features: ["tempo", "key", "energy", "spectral"],
  # Audio processing timeouts (ms)
  analyzer_timeout: 120_000,
  demucs_timeout: 300_000,
  demucs_output_dir: "/tmp/demucs",
  demucs_python: "/Users/jeremiah/.asdf/installs/python/3.11.7/bin/python3",
  min_audio_size: 1024,
  # Spotify token cache TTL (seconds, Spotify tokens expire in 3600s)
  spotify_token_ttl: 3500,
  # API token TTL (days)
  api_token_ttl_days: 30

# Configure the endpoint
config :sound_forge, SoundForgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SoundForgeWeb.ErrorHTML, json: SoundForgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SoundForge.PubSub,
  live_view: [signing_salt: "RnUPXfw7"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sound_forge, SoundForge.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sound_forge: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  sound_forge: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Oban
config :sound_forge, Oban,
  repo: SoundForge.Repo,
  queues: [download: 3, processing: 2, analysis: 2],
  plugins: [
    # Prune completed jobs after 7 days, cancelled after 1 day, discarded after 30 days
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60, limit: 10_000, interval: :timer.minutes(5)},
    # Rescue orphaned executing jobs after 30 minutes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    # Run storage cleanup daily at 3am UTC
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", SoundForge.Jobs.CleanupWorker}
     ]}
  ]

# Register audio MIME types not in default database
config :mime, :types, %{
  "audio/flac" => ["flac"],
  "audio/aac" => ["aac"],
  "audio/ogg" => ["ogg"],
  "audio/x-m4a" => ["m4a"],
  "audio/x-ms-wma" => ["wma"],
  "application/x-traktor-settings" => ["tsi"],
  "application/x-touchosc" => ["touchosc"],
  "application/x-mpc-program" => ["xpm"],
  "application/x-mpc-legacy-program" => ["pgm"]
}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :track_id, :job_id, :worker, :stage, :oban_job_id, :oban_queue, :oban_worker, :oban_attempt, :spotdl_cmd]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
