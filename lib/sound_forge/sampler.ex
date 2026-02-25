defmodule SoundForge.Sampler do
  @moduledoc """
  The Sampler context.

  Manages pad banks and individual pad assignments for the chromatic pads
  instrument. Each user can create multiple banks of 16 pads (4x4 grid),
  assign stems to pads, and configure per-pad playback settings.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.Sampler.Bank
  alias SoundForge.Sampler.Pad
  alias SoundForge.Sampler.PresetParser
  alias SoundForge.MIDI.Mappings, as: MIDIMappings

  # ---------------------------------------------------------------------------
  # Bank functions
  # ---------------------------------------------------------------------------

  @doc """
  Creates a bank for the given user with 16 empty pads pre-initialized.
  """
  @spec create_bank(map()) :: {:ok, Bank.t()} | {:error, Ecto.Changeset.t()}
  def create_bank(attrs) do
    Repo.transaction(fn ->
      case %Bank{} |> Bank.changeset(attrs) |> Repo.insert() do
        {:ok, bank} ->
          pads =
            for i <- 0..15 do
              now = DateTime.utc_now() |> DateTime.truncate(:second)

              %Pad{}
              |> Pad.changeset(%{index: i, bank_id: bank.id})
              |> Ecto.Changeset.put_change(:inserted_at, now)
              |> Ecto.Changeset.put_change(:updated_at, now)
              |> Repo.insert!()
            end

          %{bank | pads: pads}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Lists all banks for a user, ordered by position, with pads preloaded.
  """
  @spec list_banks(term()) :: [Bank.t()]
  def list_banks(user_id) do
    Bank
    |> where([b], b.user_id == ^user_id)
    |> order_by([b], asc: b.position)
    |> preload(pads: ^from(p in Pad, order_by: [asc: p.index], preload: [:stem]))
    |> Repo.all()
  end

  @doc """
  Gets a single bank with pads preloaded.
  """
  @spec get_bank!(binary()) :: Bank.t()
  def get_bank!(id) do
    Bank
    |> preload(pads: ^from(p in Pad, order_by: [asc: p.index], preload: [:stem]))
    |> Repo.get!(id)
  end

  @doc """
  Updates a bank's attributes (name, color, bpm, etc.).
  """
  @spec update_bank(Bank.t(), map()) :: {:ok, Bank.t()} | {:error, Ecto.Changeset.t()}
  def update_bank(%Bank{} = bank, attrs) do
    bank
    |> Bank.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bank and all its pads (cascade).
  """
  @spec delete_bank(Bank.t()) :: {:ok, Bank.t()} | {:error, Ecto.Changeset.t()}
  def delete_bank(%Bank{} = bank) do
    Repo.delete(bank)
  end

  # ---------------------------------------------------------------------------
  # Pad functions
  # ---------------------------------------------------------------------------

  @doc """
  Gets a single pad with its stem preloaded.
  """
  @spec get_pad!(binary()) :: Pad.t()
  def get_pad!(id) do
    Pad
    |> preload(:stem)
    |> Repo.get!(id)
  end

  @doc """
  Assigns a stem to a pad by stem_id. Pass `nil` to clear the assignment.
  """
  @spec assign_stem_to_pad(Pad.t(), binary() | nil) :: {:ok, Pad.t()} | {:error, Ecto.Changeset.t()}
  def assign_stem_to_pad(%Pad{} = pad, stem_id) do
    pad
    |> Pad.changeset(%{stem_id: stem_id})
    |> Repo.update()
    |> case do
      {:ok, pad} -> {:ok, Repo.preload(pad, :stem, force: true)}
      error -> error
    end
  end

  @doc """
  Updates playback settings on a pad (volume, pitch, velocity, start_time, end_time, label, color).
  """
  @spec update_pad(Pad.t(), map()) :: {:ok, Pad.t()} | {:error, Ecto.Changeset.t()}
  def update_pad(%Pad{} = pad, attrs) do
    pad
    |> Pad.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, pad} -> {:ok, Repo.preload(pad, :stem, force: true)}
      error -> error
    end
  end

  @doc """
  Clears the stem assignment from a pad and resets playback settings.
  """
  @spec clear_pad(Pad.t()) :: {:ok, Pad.t()} | {:error, Ecto.Changeset.t()}
  def clear_pad(%Pad{} = pad) do
    pad
    |> Pad.changeset(%{
      stem_id: nil,
      label: nil,
      color: "#6b7280",
      volume: 1.0,
      pitch: 0.0,
      velocity: 1.0,
      start_time: 0.0,
      end_time: nil
    })
    |> Repo.update()
    |> case do
      {:ok, pad} -> {:ok, Repo.preload(pad, :stem, force: true)}
      error -> error
    end
  end

  @doc """
  Quick-loads stems into a bank starting at pad index 0.
  Assigns each stem to consecutive pads, labelling them by stem type.
  Returns the updated bank with pads preloaded.
  """
  @spec quick_load_stems(Bank.t(), [SoundForge.Music.Stem.t()]) :: {:ok, Bank.t()}
  def quick_load_stems(%Bank{} = bank, stems) when is_list(stems) do
    bank = get_bank!(bank.id)

    Enum.zip(bank.pads, stems)
    |> Enum.each(fn {pad, stem} ->
      label = stem.stem_type |> to_string() |> String.capitalize()
      color = stem_type_color(stem.stem_type)

      pad
      |> Pad.changeset(%{stem_id: stem.id, label: label, color: color})
      |> Repo.update!()
    end)

    {:ok, get_bank!(bank.id)}
  end

  # ---------------------------------------------------------------------------
  # Preset Import
  # ---------------------------------------------------------------------------

  @doc """
  Imports a preset file into a new bank, parsing pad assignments and MIDI mappings.

  Accepts .touchosc, .xpm, and .pgm formats. Creates a new bank with the
  preset's pad configuration and associated MIDI mappings.

  ## Parameters
    - `user_id` - the owning user
    - `file_binary` - raw file bytes
    - `filename` - original filename (used for format detection)
    - `opts` - optional overrides: `:bank_name`, `:device_name`

  ## Returns
    - `{:ok, bank}` with the newly created bank
    - `{:error, reason}` on parse or DB failure
  """
  @spec import_preset(term(), binary(), String.t(), keyword()) ::
          {:ok, Bank.t()} | {:error, String.t()}
  def import_preset(user_id, file_binary, filename, opts \\ []) do
    case PresetParser.parse(file_binary, filename) do
      {:ok, preset_data} ->
        bank_name = Keyword.get(opts, :bank_name, preset_data.name || "Imported Bank")
        device_name = Keyword.get(opts, :device_name, "Web MIDI")
        position = length(list_banks(user_id))

        case create_bank(%{name: bank_name, user_id: user_id, position: position}) do
          {:ok, bank} ->
            # Apply pad settings from preset
            apply_preset_pads(bank, preset_data.pads, user_id)

            # Create MIDI mappings from preset
            if preset_data.midi_mappings && preset_data.midi_mappings != [] do
              source = to_string(preset_data.format)

              MIDIMappings.import_preset_mappings(
                user_id,
                bank.id,
                device_name,
                preset_data.midi_mappings,
                source
              )
            end

            # Return freshly loaded bank
            {:ok, get_bank!(bank.id)}

          {:error, changeset} ->
            {:error, "Failed to create bank: #{inspect(changeset.errors)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_preset_pads(bank, preset_pads, _user_id) do
    bank = get_bank!(bank.id)

    for preset_pad <- preset_pads do
      idx = preset_pad.index

      case Enum.find(bank.pads, &(&1.index == idx)) do
        nil ->
          :skip

        pad ->
          attrs = %{
            label: preset_pad.label,
            volume: preset_pad.volume,
            pitch: preset_pad.pitch,
            velocity: 1.0
          }

          # Set a color based on pad index for visual variety
          color = Enum.at(pad_import_colors(), rem(idx, length(pad_import_colors())))
          attrs = Map.put(attrs, :color, color)

          update_pad(pad, attrs)
      end
    end
  end

  defp pad_import_colors do
    ~w(#ef4444 #f97316 #eab308 #22c55e #3b82f6 #8b5cf6 #ec4899 #06b6d4
       #a855f7 #f43f5e #84cc16 #14b8a6 #6366f1 #e879f9 #fb923c #38bdf8)
  end

  @doc """
  Returns the MIDI mappings for a bank, suitable for sending to the JS client.
  """
  @spec bank_midi_mappings(binary(), binary()) :: [map()]
  def bank_midi_mappings(user_id, bank_id) do
    MIDIMappings.list_bank_mappings(user_id, bank_id)
    |> Enum.map(fn m ->
      %{
        midi_type: to_string(m.midi_type),
        channel: m.channel,
        number: m.number,
        action: to_string(m.action),
        parameter_index: m.parameter_index
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @stem_colors %{
    vocals: "#3b82f6",
    drums: "#ef4444",
    bass: "#22c55e",
    other: "#a855f7",
    guitar: "#f97316",
    piano: "#eab308",
    electric_guitar: "#f97316",
    acoustic_guitar: "#92400e",
    synth: "#ec4899",
    strings: "#8b5cf6",
    wind: "#06b6d4"
  }

  @doc false
  def stem_type_color(type) when is_atom(type) do
    Map.get(@stem_colors, type, "#6b7280")
  end

  def stem_type_color(type) when is_binary(type) do
    stem_type_color(String.to_existing_atom(type))
  rescue
    ArgumentError -> "#6b7280"
  end

  def stem_type_color(_), do: "#6b7280"
end
