defmodule SoundForge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Spotify HTTP client ETS table for token caching
    SoundForge.Spotify.HTTPClient.init()

    # Ensure upload directories exist
    SoundForge.Storage.ensure_directories!()

    children = [
      SoundForgeWeb.Telemetry,
      SoundForge.Repo,
      {DNSCluster, query: Application.get_env(:sound_forge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SoundForge.PubSub},
      # Task.Supervisor for async LiveView operations (e.g., SpotDL metadata fetch)
      {Task.Supervisor, name: SoundForge.TaskSupervisor},
      # DynamicSupervisor for audio processing port processes
      SoundForge.Audio.PortSupervisor,
      # ETS-backed notification store
      SoundForge.Notifications,
      # Start Oban for background job processing
      {Oban, Application.fetch_env!(:sound_forge, Oban)},
      # Oban telemetry handler for job lifecycle tracking
      SoundForge.Telemetry.ObanHandler,
      # Start to serve requests, typically the last entry
      SoundForgeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SoundForge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SoundForgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
