defmodule SoundForge.Audio.PlaybackBus do
  @moduledoc """
  Canonical playback state source for the entire application.

  Before this module, `playback_state` was siloed in three places:
  - `DashboardLive`: `:spotify_alchemy_playing`
  - `CrateDiggerLive`: `:playback_state` / `:now_playing_id`
  - `MIDI.Clock`: authoritative transport state

  PlaybackBus provides a single `state/0` call and broadcasts changes
  on `"playback:state"` so all LiveViews stay in sync regardless of
  which source triggered the play/pause.

  ## PubSub topic

      "playback:state"

  ## Broadcast payload

      {:playback_state_changed, %{playing: bool, track_id: id | nil,
                                  position_ms: integer, source: atom | nil}}

  ## Usage

      # From MIDI Clock
      PlaybackBus.play(track_id, :midi_clock)

      # From DJ deck UI
      PlaybackBus.play(track_id, :dj_deck)

      # Read current state anywhere without going through GenServer
      PlaybackBus.state()
  """

  use GenServer

  alias Phoenix.PubSub

  @topic "playback:state"
  @table :playback_bus_state

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Read current playback state directly from ETS (zero GenServer overhead)."
  def state do
    case :ets.lookup(@table, :state) do
      [{:state, s}] -> s
      [] -> default_state()
    end
  rescue
    _ -> default_state()
  end

  @doc "Update one or more playback fields and broadcast the new state."
  def update(attrs) when is_map(attrs) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      pid -> GenServer.call(pid, {:update, attrs})
    end
  end

  @doc "Mark a track as playing."
  def play(track_id, source \\ nil),
    do: update(%{playing: true, track_id: track_id, source: source})

  @doc "Pause without clearing the track."
  def pause, do: update(%{playing: false})

  @doc "Stop and clear the current track."
  def stop, do: update(%{playing: false, track_id: nil, position_ms: 0, source: nil})

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    state = default_state()
    :ets.insert(@table, {:state, state})
    {:ok, state}
  end

  @impl true
  def handle_call({:update, attrs}, _from, state) do
    new_state = Map.merge(state, attrs)
    :ets.insert(@table, {:state, new_state})
    PubSub.broadcast(SoundForge.PubSub, @topic, {:playback_state_changed, new_state})
    {:reply, new_state, new_state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp default_state do
    %{playing: false, track_id: nil, position_ms: 0, source: nil}
  end
end
