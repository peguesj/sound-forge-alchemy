defmodule SoundForge.MIDI.Mappings do
  @moduledoc """
  Context for managing MIDI controller mappings.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo
  alias SoundForge.MIDI.Mapping

  @doc """
  Lists all MIDI mappings for a given user.
  """
  @spec list_mappings(binary()) :: [Mapping.t()]
  def list_mappings(user_id) do
    Mapping
    |> where([m], m.user_id == ^user_id)
    |> order_by([m], asc: m.device_name, asc: m.number)
    |> Repo.all()
  end

  @doc """
  Creates a MIDI mapping.
  """
  @spec create_mapping(map()) :: {:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}
  def create_mapping(attrs) do
    %Mapping{}
    |> Mapping.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upsert a DJ MIDI mapping. If a mapping already exists for the same
  (user_id, device_name, number), update its action/params. Otherwise insert.
  """
  def upsert_dj_mapping(%{user_id: uid, device_name: dev, number: num} = attrs) do
    case Repo.get_by(Mapping, user_id: uid, device_name: dev, number: num) do
      nil ->
        %Mapping{}
        |> Mapping.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Mapping.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes a MIDI mapping.
  """
  @spec delete_mapping(Mapping.t()) :: {:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}
  def delete_mapping(%Mapping{} = mapping) do
    Repo.delete(mapping)
  end

  @doc "Update a mapping's fields."
  def update_mapping(%Mapping{} = mapping, attrs) do
    mapping
    |> Mapping.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Find a single mapping by user, device, and MIDI number (note/CC).
  Used by MIDI learn to detect if a control is already bound.
  """
  @spec get_mapping_for_control(integer(), String.t(), integer()) :: Mapping.t() | nil
  def get_mapping_for_control(user_id, device_name, number) do
    Mapping
    |> where([m], m.user_id == ^user_id and m.device_name == ^device_name and m.number == ^number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns all mappings for a specific user and device.
  """
  @spec get_mappings_for_device(binary(), String.t()) :: [Mapping.t()]
  def get_mappings_for_device(user_id, device_name) do
    Mapping
    |> where([m], m.user_id == ^user_id and m.device_name == ^device_name)
    |> order_by([m], asc: m.number)
    |> Repo.all()
  end

  @doc """
  Returns the default generic controller preset mappings as attribute maps.

  These can be inserted for a user via `create_mapping/1`:

  - CC1 -> volume (stem_volume, master target)
  - CC7 -> pan (stem_volume, pan target)
  - CC64 -> sustain (stem_mute, hold behavior)
  """
  @spec default_generic_preset(binary()) :: [map()]
  def default_generic_preset(user_id) do
    device = "Generic MIDI Controller"

    [
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 1,
        action: :stem_volume,
        params: %{"target" => "master"}
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 7,
        action: :stem_volume,
        params: %{"target" => "pan"}
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 64,
        action: :stem_mute,
        params: %{"behavior" => "hold"}
      }
    ]
  end

  @doc """
  Inserts the default generic preset for a user. Returns list of results.
  """
  @spec insert_default_preset(binary()) :: [{:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}]
  def insert_default_preset(user_id) do
    user_id
    |> default_generic_preset()
    |> Enum.map(&create_mapping/1)
  end

  @doc """
  Returns default DJ controller preset mappings as attribute maps.

  Maps a standard DJ controller layout:

    - Note 48/49 (C3/C#3) -> Deck 1/2 play/pause
    - CC1 -> crossfader
    - CC2/CC3 -> Deck 1/2 pitch fader
    - Notes 50-51 (D3/D#3) -> Deck 1 hot cues 1-2
    - CC20/CC21 -> Deck 1/2 loop toggle
  """
  @spec default_dj_preset(binary()) :: [map()]
  def default_dj_preset(user_id) do
    device = "DJ Controller"

    [
      # Deck 1 play/pause - Note C3 (note 48)
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 48,
        action: :dj_play,
        params: %{"deck" => "1"}
      },
      # Deck 2 play/pause - Note C#3 (note 49)
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 49,
        action: :dj_play,
        params: %{"deck" => "2"}
      },
      # Crossfader - CC1
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 1,
        action: :dj_crossfader,
        params: %{}
      },
      # Deck 1 pitch fader - CC2
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 2,
        action: :dj_pitch,
        params: %{"deck" => "1"}
      },
      # Deck 2 pitch fader - CC3
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 3,
        action: :dj_pitch,
        params: %{"deck" => "2"}
      },
      # Deck 1 hot cue 1 - Note D3 (note 50)
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 50,
        action: :dj_cue,
        params: %{"deck" => "1", "slot" => "1"}
      },
      # Deck 1 hot cue 2 - Note D#3 (note 51)
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 51,
        action: :dj_cue,
        params: %{"deck" => "1", "slot" => "2"}
      },
      # Deck 1 loop toggle - CC20
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 20,
        action: :dj_loop_toggle,
        params: %{"deck" => "1"}
      },
      # Deck 2 loop toggle - CC21
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 21,
        action: :dj_loop_toggle,
        params: %{"deck" => "2"}
      }
    ]
  end

  @doc """
  Inserts the default DJ controller preset for a user. Returns list of results.
  """
  @spec insert_dj_preset(binary()) :: [{:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}]
  def insert_dj_preset(user_id) do
    user_id
    |> default_dj_preset()
    |> Enum.map(&create_mapping/1)
  end

  # ---------------------------------------------------------------------------
  # Pad-specific mapping functions
  # ---------------------------------------------------------------------------

  @doc """
  Returns all MIDI mappings scoped to a specific bank.
  """
  @spec list_bank_mappings(binary(), binary()) :: [Mapping.t()]
  def list_bank_mappings(user_id, bank_id) do
    Mapping
    |> where([m], m.user_id == ^user_id and m.bank_id == ^bank_id)
    |> order_by([m], asc: m.parameter_index, asc: m.number)
    |> Repo.all()
  end

  @doc """
  Creates or updates a MIDI mapping for a pad parameter (upsert on unique constraint).

  If a mapping already exists for the same user + device + midi_type + channel + number,
  it will be updated with the new action, bank_id, and parameter_index.
  """
  @spec upsert_pad_mapping(map()) :: {:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}
  def upsert_pad_mapping(attrs) do
    existing =
      Mapping
      |> where(
        [m],
        m.user_id == ^attrs.user_id and
          m.device_name == ^attrs.device_name and
          m.midi_type == ^attrs.midi_type and
          m.channel == ^attrs.channel and
          m.number == ^attrs.number
      )
      |> Repo.one()

    case existing do
      nil ->
        create_mapping(attrs)

      mapping ->
        mapping
        |> Mapping.changeset(Map.take(attrs, [:action, :params, :bank_id, :parameter_index, :source]))
        |> Repo.update()
    end
  end

  @doc """
  Bulk-creates MIDI mappings from a parsed preset's midi_mappings list.

  Takes the normalized mapping list from `SoundForge.Sampler.PresetParser`
  and creates `Mapping` records scoped to the given user, bank, and device.
  """
  @spec import_preset_mappings(binary(), binary(), String.t(), [map()], String.t()) ::
          [{:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}]
  def import_preset_mappings(user_id, bank_id, device_name, midi_mappings, source) do
    midi_mappings
    |> Enum.map(fn mapping ->
      midi_type = normalize_midi_type(mapping.midi_type)
      action = normalize_pad_action(mapping.parameter_type)

      attrs = %{
        user_id: user_id,
        device_name: device_name,
        midi_type: midi_type,
        channel: mapping.midi_channel,
        number: mapping.midi_number,
        action: action,
        bank_id: bank_id,
        parameter_index: mapping.parameter_index,
        params: %{},
        source: source
      }

      upsert_pad_mapping(attrs)
    end)
  end

  @doc """
  Deletes all pad-scoped mappings for a specific bank.
  """
  @spec delete_bank_mappings(binary(), binary()) :: {non_neg_integer(), nil}
  def delete_bank_mappings(user_id, bank_id) do
    Mapping
    |> where([m], m.user_id == ^user_id and m.bank_id == ^bank_id)
    |> Repo.delete_all()
  end

  # ---------------------------------------------------------------------------
  # Universal preset functions
  # ---------------------------------------------------------------------------

  @doc """
  Returns the full universal preset mappings for an Akai MPC Live II.

  Covers all tab contexts: transport, DJ, DAW, Library, and Sampler.
  Uses CC 118=play, CC 117=stop, CC 119=rec as the MPC Live II transport
  fingerprint (channel 0), plus pad Note triggers (Notes 36–51).

  Returned maps include `preset_name: "mpc_live2_universal"` and
  `tab_context` per-mapping so the UI can filter by active tab.
  """
  @spec default_mpc_live2_preset(term()) :: [map()]
  def default_mpc_live2_preset(user_id) do
    device = "Akai MPC Live II"
    preset = "mpc_live2_universal"

    [
      # --- Transport (universal) ---
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 118,
        action: :play,
        params: %{},
        tab_context: "universal",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 117,
        action: :stop,
        params: %{},
        tab_context: "universal",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 119,
        action: :bpm_tap,
        params: %{},
        tab_context: "universal",
        preset_name: preset
      },
      # --- DJ context ---
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 113,
        action: :dj_loop_toggle,
        params: %{"deck" => "1"},
        tab_context: "dj",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 1,
        action: :dj_crossfader,
        params: %{},
        tab_context: "dj",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 7,
        action: :dj_pitch,
        params: %{"deck" => "1"},
        tab_context: "dj",
        preset_name: preset
      },
      # --- DAW context ---
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 114,
        action: :daw_loop,
        params: %{},
        tab_context: "daw",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 115,
        action: :daw_record,
        params: %{},
        tab_context: "daw",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 116,
        action: :daw_metronome,
        params: %{},
        tab_context: "daw",
        preset_name: preset
      },
      # --- Library context ---
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 26,
        action: :library_next,
        params: %{},
        tab_context: "library",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 27,
        action: :library_prev,
        params: %{},
        tab_context: "library",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :cc,
        channel: 0,
        number: 28,
        action: :library_select,
        params: %{},
        tab_context: "library",
        preset_name: preset
      },
      # --- Sampler pads (Notes 36-51) ---
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 36,
        action: :sampler_pad,
        params: %{"pad" => 1},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 37,
        action: :sampler_pad,
        params: %{"pad" => 2},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 38,
        action: :sampler_pad,
        params: %{"pad" => 3},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 39,
        action: :sampler_pad,
        params: %{"pad" => 4},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 40,
        action: :sampler_pad,
        params: %{"pad" => 5},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 41,
        action: :sampler_pad,
        params: %{"pad" => 6},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 42,
        action: :sampler_pad,
        params: %{"pad" => 7},
        tab_context: "sampler",
        preset_name: preset
      },
      %{
        user_id: user_id,
        device_name: device,
        midi_type: :note_on,
        channel: 0,
        number: 43,
        action: :sampler_pad,
        params: %{"pad" => 8},
        tab_context: "sampler",
        preset_name: preset
      }
    ]
  end

  @doc """
  Inserts the full MPC Live II universal preset for a user.

  Returns a list of `{:ok, Mapping.t()}` or `{:error, Ecto.Changeset.t()}`.
  """
  @spec insert_mpc_live2_preset(term()) ::
          [{:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}]
  def insert_mpc_live2_preset(user_id) do
    user_id
    |> default_mpc_live2_preset()
    |> Enum.map(&create_mapping/1)
  end

  @doc """
  Deletes all mappings belonging to a named preset for a user.

  Use this to cleanly remove a universal preset before reloading it.
  """
  @spec delete_preset(term(), String.t()) :: {non_neg_integer(), nil}
  def delete_preset(user_id, preset_name) do
    Mapping
    |> where([m], m.user_id == ^user_id and m.preset_name == ^preset_name)
    |> Repo.delete_all()
  end

  @doc """
  Dispatches to the correct universal preset builder for the given controller model.

  Supported controller names (case-insensitive match):
  - `"Akai MPC Live II"` / `"mpc_live2"` — full 18-mapping universal preset

  Returns `{:ok, results}` where `results` is the list of insert outcomes,
  or `{:error, :unknown_controller}` if the model has no preset.
  """
  @spec insert_preset_for_controller(term(), String.t()) ::
          {:ok, [{:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}]}
          | {:error, :unknown_controller}
  def insert_preset_for_controller(user_id, controller_name) do
    normalized = String.downcase(controller_name)

    cond do
      String.contains?(normalized, "mpc live ii") or normalized == "mpc_live2" ->
        {:ok, insert_mpc_live2_preset(user_id)}

      true ->
        {:error, :unknown_controller}
    end
  end

  defp normalize_midi_type(:note), do: :note_on
  defp normalize_midi_type(:cc), do: :cc
  defp normalize_midi_type(:program_change), do: :cc
  defp normalize_midi_type(type) when type in [:note_on, :note_off, :cc], do: type
  defp normalize_midi_type(_), do: :cc

  defp normalize_pad_action(:pad_trigger), do: :pad_trigger
  defp normalize_pad_action(:pad_volume), do: :pad_volume
  defp normalize_pad_action(:pad_pitch), do: :pad_pitch
  defp normalize_pad_action(:pad_velocity), do: :pad_velocity
  defp normalize_pad_action(:master_volume), do: :pad_master_volume
  defp normalize_pad_action(:crossfader), do: :dj_crossfader
  defp normalize_pad_action(_), do: :pad_trigger
end
