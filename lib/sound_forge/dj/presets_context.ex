defmodule SoundForge.DJ.PresetsContext do
  @moduledoc """
  Context for managing DJ preset layout records.

  Presets persist a complete snapshot of the DJ tab state so users can
  name and restore full sessions — including deck assignments, BPM, pitch,
  loops, EQ, crossfader position, cue point sets, and stem states.

  This module is intentionally separate from `SoundForge.DJ.Presets`
  (the file-format parser) to avoid name collisions.
  """

  import Ecto.Query, warn: false

  alias SoundForge.Repo
  alias SoundForge.DJ.DjPreset

  # ---------------------------------------------------------------------------
  # CRUD
  # ---------------------------------------------------------------------------

  @doc "List all presets for a user, newest first."
  @spec list_presets(integer()) :: [DjPreset.t()]
  def list_presets(user_id) do
    DjPreset
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "Get a preset by id belonging to a specific user. Returns nil if not found or wrong owner."
  @spec get_preset(binary(), integer()) :: DjPreset.t() | nil
  def get_preset(id, user_id) do
    Repo.get_by(DjPreset, id: id, user_id: user_id)
  end

  @doc "Create a new preset. Returns `{:ok, preset}` or `{:error, changeset}`."
  @spec create_preset(map()) :: {:ok, DjPreset.t()} | {:error, Ecto.Changeset.t()}
  def create_preset(attrs) do
    %DjPreset{}
    |> DjPreset.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update the name of a preset. Returns `{:ok, preset}` or `{:error, changeset}`."
  @spec update_preset(DjPreset.t(), map()) :: {:ok, DjPreset.t()} | {:error, Ecto.Changeset.t()}
  def update_preset(%DjPreset{} = preset, attrs) do
    preset
    |> DjPreset.update_changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a preset by id + user_id. Returns `:ok` or `{:error, :not_found}`."
  @spec delete_preset(binary(), integer()) :: :ok | {:error, :not_found}
  def delete_preset(id, user_id) do
    case get_preset(id, user_id) do
      nil -> {:error, :not_found}
      preset -> Repo.delete(preset) |> then(fn _ -> :ok end)
    end
  end

  # ---------------------------------------------------------------------------
  # Layout serialization
  # ---------------------------------------------------------------------------

  @doc """
  Serialize the current DjTabComponent assigns into the canonical `layout_json` map.

  Expected keys in `assigns`:
  - `:deck_1`, `:deck_2` — deck state maps (track, tempo_bpm, pitch_adjust, etc.)
  - `:deck_1_volume`, `:deck_2_volume` — integer 0-100
  - `:crossfader` — integer -100 to +100
  - `:crossfader_curve` — string
  - `:deck_1_cue_points`, `:deck_2_cue_points` — lists of cue point maps
  - `:master_volume` — integer 0-100 (optional, defaults to 85)
  """
  @spec build_layout_json(map()) :: map()
  def build_layout_json(assigns) do
    deck_1 = Map.get(assigns, :deck_1, %{})
    deck_2 = Map.get(assigns, :deck_2, %{})

    %{
      "format_version" => "1.0",
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "decks" => %{
        "1" => serialize_deck(deck_1, Map.get(assigns, :deck_1_volume, 85)),
        "2" => serialize_deck(deck_2, Map.get(assigns, :deck_2_volume, 85))
      },
      "crossfader" => Map.get(assigns, :crossfader, 0),
      "crossfader_curve" => Map.get(assigns, :crossfader_curve, "equal_power"),
      "master_volume" => Map.get(assigns, :master_volume, 85),
      "cue_points" => serialize_cue_points(assigns),
      "stem_states" => serialize_stem_states(assigns)
    }
  end

  defp serialize_deck(deck, volume) do
    track = Map.get(deck, :track)

    %{
      "track_id" => if(track, do: to_string(track.id), else: nil),
      "track_title" => if(track, do: track.title, else: nil),
      "tempo_bpm" => Map.get(deck, :tempo_bpm),
      "pitch_adjust" => Map.get(deck, :pitch_adjust, 0.0),
      "loop_active" => Map.get(deck, :loop_active, false),
      "loop_start_ms" => Map.get(deck, :loop_start_ms),
      "loop_end_ms" => Map.get(deck, :loop_end_ms),
      "volume" => volume
    }
  end

  defp serialize_cue_points(assigns) do
    cues_1 = Map.get(assigns, :deck_1_cue_points, [])
    cues_2 = Map.get(assigns, :deck_2_cue_points, [])
    deck_1 = Map.get(assigns, :deck_1, %{})
    deck_2 = Map.get(assigns, :deck_2, %{})

    result = %{}

    result =
      case get_in(deck_1, [:track, :id]) do
        nil -> result
        id -> Map.put(result, to_string(id), Enum.map(cues_1, &serialize_cue/1))
      end

    case get_in(deck_2, [:track, :id]) do
      nil -> result
      id -> Map.put(result, to_string(id), Enum.map(cues_2, &serialize_cue/1))
    end
  end

  defp serialize_cue(cue) do
    %{
      "position_ms" => Map.get(cue, :position_ms) || Map.get(cue, "position_ms"),
      "label" => Map.get(cue, :label) || Map.get(cue, "label"),
      "color" => Map.get(cue, :color) || Map.get(cue, "color", "#8b5cf6"),
      "cue_type" => to_string(Map.get(cue, :cue_type) || Map.get(cue, "cue_type", "hot"))
    }
  end

  defp serialize_stem_states(assigns) do
    deck_1 = Map.get(assigns, :deck_1, %{})
    deck_2 = Map.get(assigns, :deck_2, %{})

    %{
      "deck_1" => extract_stem_states(deck_1),
      "deck_2" => extract_stem_states(deck_2)
    }
  end

  defp extract_stem_states(deck) do
    stems = Map.get(deck, :stems, [])

    Map.new(stems, fn stem ->
      type = to_string(Map.get(stem, :type, "unknown"))
      active = Map.get(stem, :active, true)
      {type, active}
    end)
  end

  # ---------------------------------------------------------------------------
  # Save current layout
  # ---------------------------------------------------------------------------

  @doc """
  Snapshot the current DJ tab state and persist it as a named preset.

  Returns `{:ok, %DjPreset{}}` on success, `{:error, changeset}` on failure.
  """
  @spec save_current_layout(String.t(), map(), String.t()) ::
          {:ok, DjPreset.t()} | {:error, Ecto.Changeset.t()}
  def save_current_layout(name, assigns, source \\ "manual") do
    user_id = Map.get(assigns, :current_user_id)
    layout_json = build_layout_json(assigns)

    create_preset(%{
      name: name,
      user_id: user_id,
      layout_json: layout_json,
      source: source
    })
  end

  # ---------------------------------------------------------------------------
  # Load layout
  # ---------------------------------------------------------------------------

  @doc """
  Restore a DJ session from a saved preset.

  Returns `{:ok, assigns_map}` where assigns_map can be merged directly into
  the DjTabComponent socket. Missing/deleted tracks produce empty deck states.

  Returns `{:error, :not_found}` or `{:error, :invalid_layout}` on failure.
  """
  @spec load_layout(binary(), integer()) ::
          {:ok, map()} | {:error, :not_found | :invalid_layout}
  def load_layout(preset_id, user_id) do
    case get_preset(preset_id, user_id) do
      nil ->
        {:error, :not_found}

      preset ->
        deserialize_layout(preset.layout_json)
    end
  end

  defp deserialize_layout(nil), do: {:error, :invalid_layout}

  defp deserialize_layout(layout) when is_map(layout) do
    decks_raw = Map.get(layout, "decks", %{})

    with {:ok, deck_1} <- deserialize_deck(Map.get(decks_raw, "1", %{})),
         {:ok, deck_2} <- deserialize_deck(Map.get(decks_raw, "2", %{})) do
      assigns = %{
        deck_1: deck_1.state,
        deck_2: deck_2.state,
        deck_1_volume: Map.get(decks_raw, "1", %{}) |> Map.get("volume", 85),
        deck_2_volume: Map.get(decks_raw, "2", %{}) |> Map.get("volume", 85),
        crossfader: Map.get(layout, "crossfader", 0),
        crossfader_curve: Map.get(layout, "crossfader_curve", "equal_power"),
        master_volume: Map.get(layout, "master_volume", 85)
      }

      {:ok, assigns}
    end
  end

  defp deserialize_layout(_), do: {:error, :invalid_layout}

  defp deserialize_deck(deck_raw) when is_map(deck_raw) do
    track =
      case Map.get(deck_raw, "track_id") do
        nil -> nil
        "" -> nil
        id -> load_track_safely(id)
      end

    state = %{
      track: track,
      playing: false,
      position: 0.0,
      tempo_bpm: Map.get(deck_raw, "tempo_bpm"),
      pitch_adjust: Map.get(deck_raw, "pitch_adjust", 0.0),
      loop_active: Map.get(deck_raw, "loop_active", false),
      loop_start_ms: Map.get(deck_raw, "loop_start_ms"),
      loop_end_ms: Map.get(deck_raw, "loop_end_ms"),
      stems: if(track, do: [], else: []),
      audio_urls: [],
      midi_sync: false,
      structure: nil,
      loop_points: [],
      bar_times: [],
      arrangement_markers: [],
      current_section: nil
    }

    {:ok, %{state: state}}
  end

  defp deserialize_deck(_), do: {:ok, %{state: empty_deck_state()}}

  defp load_track_safely(id) do
    try do
      SoundForge.Music.get_track(id)
    rescue
      _ -> nil
    end
  end

  defp empty_deck_state do
    %{
      track: nil,
      playing: false,
      position: 0.0,
      tempo_bpm: nil,
      pitch_adjust: 0.0,
      loop_active: false,
      loop_start_ms: nil,
      loop_end_ms: nil,
      stems: [],
      audio_urls: [],
      midi_sync: false,
      structure: nil,
      loop_points: [],
      bar_times: [],
      arrangement_markers: [],
      current_section: nil
    }
  end
end
