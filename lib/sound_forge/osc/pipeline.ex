defmodule SoundForge.OSC.Pipeline do
  @moduledoc """
  End-to-end OSC pipeline integration.

  Provides simulation and verification functions for the full TouchOSC pipeline:
  TouchOSC -> OSC Server -> ActionExecutor -> PubSub -> LiveView -> OSC feedback
  """

  alias SoundForge.OSC.Parser

  require Logger

  @doc """
  Simulate an OSC message as if it came from TouchOSC.
  Sends a UDP packet to the local OSC server.
  """
  @spec simulate_osc(String.t(), [term()], keyword()) :: :ok | {:error, term()}
  def simulate_osc(address, args \\ [], opts \\ []) do
    host = Keyword.get(opts, :host, "127.0.0.1")
    port = Keyword.get(opts, :port, 8000)

    data = Parser.encode(address, args)

    case :gen_udp.open(0, [:binary]) do
      {:ok, socket} ->
        result = :gen_udp.send(socket, String.to_charlist(host), port, data)
        :gen_udp.close(socket)
        Logger.debug("OSC Pipeline: simulated #{address} #{inspect(args)} -> port #{port}")
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Simulate a stem volume change from TouchOSC.
  """
  @spec simulate_stem_volume(integer(), float(), keyword()) :: :ok | {:error, term()}
  def simulate_stem_volume(stem, value, opts \\ []) when is_integer(stem) and is_float(value) do
    simulate_osc("/stem/#{stem}/volume", [value], opts)
  end

  @doc """
  Simulate a transport action from TouchOSC.
  """
  @spec simulate_transport(atom(), keyword()) :: :ok | {:error, term()}
  def simulate_transport(action, opts \\ []) when action in [:play, :stop, :next, :prev] do
    simulate_osc("/transport/#{action}", [1.0], opts)
  end

  @doc """
  Simulate a pad trigger from TouchOSC.
  """
  @spec simulate_pad(integer(), float(), keyword()) :: :ok | {:error, term()}
  def simulate_pad(pad_number, velocity \\ 1.0, opts \\ []) do
    simulate_osc("/pad/#{pad_number}", [velocity], opts)
  end

  @doc """
  Run a full pipeline test: send OSC, verify PubSub receives it.
  Returns timing information.
  """
  @spec test_pipeline(String.t(), [term()], keyword()) :: {:ok, map()} | {:error, term()}
  def test_pipeline(address, args \\ [], opts \\ []) do
    topic = Keyword.get(opts, :topic, "track_playback")
    timeout = Keyword.get(opts, :timeout, 1000)

    Phoenix.PubSub.subscribe(SoundForge.PubSub, topic)

    start_time = System.monotonic_time(:microsecond)

    case simulate_osc(address, args, opts) do
      :ok ->
        receive do
          msg ->
            end_time = System.monotonic_time(:microsecond)
            latency_us = end_time - start_time
            Phoenix.PubSub.unsubscribe(SoundForge.PubSub, topic)

            {:ok,
             %{
               address: address,
               args: args,
               received: msg,
               latency_us: latency_us,
               latency_ms: latency_us / 1000.0
             }}
        after
          timeout ->
            Phoenix.PubSub.unsubscribe(SoundForge.PubSub, topic)
            {:error, :timeout}
        end

      error ->
        Phoenix.PubSub.unsubscribe(SoundForge.PubSub, topic)
        error
    end
  end

  @doc """
  Run a batch of pipeline tests and return summary.
  """
  @spec benchmark(integer(), keyword()) :: map()
  def benchmark(iterations \\ 10, opts \\ []) do
    results =
      1..iterations
      |> Enum.map(fn i ->
        value = i / iterations
        test_pipeline("/stem/1/volume", [value], opts)
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    failures = Enum.filter(results, &match?({:error, _}, &1))

    latencies =
      successes
      |> Enum.map(fn {:ok, %{latency_ms: ms}} -> ms end)

    %{
      total: iterations,
      successes: length(successes),
      failures: length(failures),
      avg_latency_ms: if(latencies != [], do: Enum.sum(latencies) / length(latencies), else: nil),
      min_latency_ms: if(latencies != [], do: Enum.min(latencies), else: nil),
      max_latency_ms: if(latencies != [], do: Enum.max(latencies), else: nil),
      p99_latency_ms: percentile(latencies, 99)
    }
  end

  defp percentile([], _p), do: nil

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    idx = round(p / 100.0 * length(sorted)) - 1
    idx = max(0, min(idx, length(sorted) - 1))
    Enum.at(sorted, idx)
  end
end
