defmodule SoundForge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    check_port_available!()

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
      # ETS-backed audio prefetch cache for DJ/DAW modes
      SoundForge.Audio.Prefetch,
      # Start Oban for background job processing
      {Oban, Application.fetch_env!(:sound_forge, Oban)},
      # Oban telemetry handler for job lifecycle tracking
      SoundForge.Telemetry.ObanHandler,
      # MIDI device discovery and hotplug monitoring
      SoundForge.MIDI.DeviceManager,
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

  # Checks if the configured HTTP port is available before starting the
  # supervision tree. Only runs in dev/test where Mix is available.
  defp check_port_available! do
    endpoint_config = Application.get_env(:sound_forge, SoundForgeWeb.Endpoint, [])
    http_config = Keyword.get(endpoint_config, :http, [])
    port = Keyword.get(http_config, :port, 4000)
    server_enabled = Keyword.get(endpoint_config, :server, true)

    if server_enabled and Code.ensure_loaded?(Mix) do
      case :gen_tcp.connect(~c"localhost", port, [], 1_000) do
        {:ok, socket} ->
          :gen_tcp.close(socket)

          Mix.raise("""
          Port #{port} is already in use.

          Kill the existing process:  kill $(lsof -ti:#{port})
          Or use a different port:    PORT=#{port + 1} mix phx.server
          """)

        {:error, _} ->
          :ok
      end
    else
      :ok
    end
  end
end
