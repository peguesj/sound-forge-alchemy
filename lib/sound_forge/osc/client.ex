defmodule SoundForge.OSC.Client do
  @moduledoc "Sends OSC messages to a target host:port (e.g., TouchOSC device)."
  require Logger

  @type osc_arg :: float() | integer() | String.t() | binary()

  @doc "Send an OSC message to the given host and port via an ephemeral UDP socket."
  @spec send(String.t(), integer(), String.t(), [osc_arg()]) :: :ok | {:error, term()}
  def send(host, port, address, args \\ []) do
    data = SoundForge.OSC.Parser.encode(address, args)
    host_charlist = String.to_charlist(host)

    case :gen_udp.open(0, [:binary]) do
      {:ok, socket} ->
        result = :gen_udp.send(socket, host_charlist, port, data)
        :gen_udp.close(socket)
        result

      {:error, reason} ->
        Logger.warning("OSC Client send failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
