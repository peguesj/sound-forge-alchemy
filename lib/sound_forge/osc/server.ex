defmodule SoundForge.OSC.Server do
  @moduledoc "GenServer that listens for OSC messages on a configurable UDP port."
  use GenServer
  require Logger

  @default_port 8000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def get_port(server \\ __MODULE__), do: GenServer.call(server, :get_port)

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, @default_port)

    case :gen_udp.open(port, [:binary, active: true, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("OSC Server listening on UDP port #{port}")
        {:ok, %{socket: socket, port: port}}

      {:error, reason} ->
        Logger.warning("OSC Server failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %{socket: nil, port: port}}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state), do: {:reply, state.port, state}

  @impl true
  def handle_info({:udp, _socket, ip, sender_port, data}, state) do
    case SoundForge.OSC.Parser.decode(data) do
      {:ok, messages} ->
        Enum.each(messages, fn msg ->
          Phoenix.PubSub.broadcast(
            SoundForge.PubSub,
            "osc:messages",
            {:osc_message, msg, {ip, sender_port}}
          )
        end)

      {:error, reason} ->
        Logger.debug("OSC parse error: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: socket}) when not is_nil(socket) do
    :gen_udp.close(socket)
  end

  def terminate(_reason, _state), do: :ok
end
