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
  Deletes a MIDI mapping.
  """
  @spec delete_mapping(Mapping.t()) :: {:ok, Mapping.t()} | {:error, Ecto.Changeset.t()}
  def delete_mapping(%Mapping{} = mapping) do
    Repo.delete(mapping)
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
end
