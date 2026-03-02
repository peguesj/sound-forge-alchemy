defmodule SoundForge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    worker_mode = Application.get_env(:sound_forge, :worker_mode, "full")

    unless worker_mode == "gpu_worker" do
      check_port_available!()
      # Initialize Spotify HTTP client ETS table for token caching
      SoundForge.Spotify.HTTPClient.init()
    end

    # Ensure upload directories exist
    SoundForge.Storage.ensure_directories!()

    children =
      core_children() ++
        web_children(worker_mode) ++
        midi_children(worker_mode)

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

  # Core children started in ALL worker modes
  defp core_children do
    [
      SoundForgeWeb.Telemetry,
      SoundForge.Vault,
      SoundForge.Repo,
      {DNSCluster, query: Application.get_env(:sound_forge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SoundForge.PubSub},
      {Task.Supervisor, name: SoundForge.TaskSupervisor},
      SoundForge.Audio.PortSupervisor,
      {Oban, Application.fetch_env!(:sound_forge, Oban)}
    ]
  end

  # Web-facing children: notifications, prefetch, telemetry handlers,
  # LLM registry, and the HTTP endpoint. Skipped for gpu_worker mode.
  defp web_children("gpu_worker"), do: []

  defp web_children(_mode) do
    swoosh_children() ++
      [
        SoundForge.Notifications,
        SoundForge.Audio.Prefetch,
        SoundForge.Telemetry.ObanHandler,
        SoundForge.LLM.ModelRegistry,
        SoundForgeWeb.Endpoint
      ]
  end

  # Start Swoosh local email storage when the local adapter is configured.
  # Required for dev and QA environments that use Swoosh.Adapters.Local.
  # In test, the adapter is Swoosh.Adapters.Test (no GenServer needed).
  # In production with a real SMTP/API adapter, this list is empty.
  defp swoosh_children do
    case Application.get_env(:sound_forge, SoundForge.Mailer, [])[:adapter] do
      Swoosh.Adapters.Local ->
        [{Swoosh.Adapters.Local, storage_driver: Swoosh.Adapters.Local.Storage.Memory}]

      _ ->
        []
    end
  end

  # MIDI device monitoring only in "full" mode (local dev with hardware).
  # Disabled in "web" and "gpu_worker" container modes.
  defp midi_children("full") do
    [
      SoundForge.MIDI.DeviceManager,
      SoundForge.MIDI.Dispatcher
    ]
  end

  defp midi_children(_mode), do: []

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
