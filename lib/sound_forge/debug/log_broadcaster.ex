defmodule SoundForge.Debug.LogBroadcaster do
  @moduledoc """
  Custom Logger backend that broadcasts log events to PubSub topic "debug:logs".

  Each broadcast includes level, message, timestamp, metadata, and namespace
  (extracted from [bracket.prefix] pattern). Only active in dev environment.
  """
  @behaviour :gen_event

  @pubsub SoundForge.PubSub
  @topic "debug:logs"

  @doc "Returns the PubSub topic for debug log events."
  def topic, do: @topic

  # -- :gen_event callbacks --

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_event({level, _gl, {Logger, message, timestamp, metadata}}, state) do
    msg =
      try do
        IO.iodata_to_binary(message)
      rescue
        ArgumentError -> inspect(message)
      end

    namespace = extract_namespace(msg)

    event = %{
      level: level,
      message: msg,
      timestamp: format_timestamp(timestamp),
      metadata: Map.new(metadata),
      namespace: namespace
    }

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:debug_log, event})

    {:ok, state}
  end

  def handle_event(:flush, state), do: {:ok, state}
  def handle_event(_, state), do: {:ok, state}

  @impl true
  def handle_call({:configure, _opts}, state), do: {:ok, :ok, state}

  @impl true
  def handle_info(_, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  # -- Private --

  defp extract_namespace(msg) do
    case Regex.run(~r/^\[([^\]]+)\]/, msg) do
      [_, ns] -> ns
      _ -> nil
    end
  end

  defp format_timestamp({date, {h, m, s, ms}}) do
    {year, month, day} = date

    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B.~3..0B", [
      year,
      month,
      day,
      h,
      m,
      s,
      ms
    ])
    |> IO.iodata_to_binary()
  end
end
