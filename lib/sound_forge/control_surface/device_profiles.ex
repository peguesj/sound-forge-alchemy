defmodule SoundForge.ControlSurface.DeviceProfiles do
  @moduledoc """
  Context for managing control surface device profiles.

  Device profiles store collections of control mappings for MIDI/OSC hardware.
  Profiles can be created manually via MIDI Learn or imported from external
  files (TSI, Rekordbox, TouchOSC).

  ## Usage

      # List all profiles for a user
      profiles = DeviceProfiles.list_profiles(user_id)

      # Create a new profile
      {:ok, profile} = DeviceProfiles.create_profile(%{
        name: "My Controller",
        source: :midi_learn,
        user_id: user_id,
        device_id: "midi:input:0",
        mappings: %{
          "cc:0:1" => %{"action" => :stem_volume, "params" => %{"target" => "master"}}
        }
      })

      # Import from TSI/Rekordbox/TouchOSC (Wave 2)
      {:ok, profile} = DeviceProfiles.import_profile("/path/to/controller.tsi", user_id)
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo
  alias SoundForge.ControlSurface.DeviceProfile

  @doc """
  List all device profiles for a user.
  """
  @spec list_profiles(integer()) :: [DeviceProfile.t()]
  def list_profiles(user_id) do
    DeviceProfile
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Get a single device profile by ID.
  """
  @spec get_profile(binary()) :: DeviceProfile.t() | nil
  def get_profile(id) do
    Repo.get(DeviceProfile, id)
  end

  @doc """
  Get a profile by user ID and device ID.
  """
  @spec get_profile_by_device(integer(), String.t()) :: DeviceProfile.t() | nil
  def get_profile_by_device(user_id, device_id) do
    DeviceProfile
    |> where([p], p.user_id == ^user_id and p.device_id == ^device_id)
    |> order_by([p], desc: p.updated_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Create a new device profile.
  """
  @spec create_profile(map()) :: {:ok, DeviceProfile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(attrs) do
    %DeviceProfile{}
    |> DeviceProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update an existing device profile.
  """
  @spec update_profile(DeviceProfile.t(), map()) ::
          {:ok, DeviceProfile.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%DeviceProfile{} = profile, attrs) do
    profile
    |> DeviceProfile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a device profile.
  """
  @spec delete_profile(DeviceProfile.t()) ::
          {:ok, DeviceProfile.t()} | {:error, Ecto.Changeset.t()}
  def delete_profile(%DeviceProfile{} = profile) do
    Repo.delete(profile)
  end

  @doc """
  Add or update a single control mapping in a profile.

  ## Examples

      profile = DeviceProfiles.get_profile(profile_id)
      {:ok, updated} = DeviceProfiles.add_mapping(
        profile,
        "cc:0:1",
        %{"action" => :stem_volume, "params" => %{"target" => "master"}}
      )
  """
  @spec add_mapping(DeviceProfile.t(), String.t(), map()) ::
          {:ok, DeviceProfile.t()} | {:error, Ecto.Changeset.t()}
  def add_mapping(%DeviceProfile{} = profile, control_id, mapping) do
    updated_mappings = Map.put(profile.mappings, control_id, mapping)

    update_profile(profile, %{mappings: updated_mappings})
  end

  @doc """
  Remove a control mapping from a profile.
  """
  @spec remove_mapping(DeviceProfile.t(), String.t()) ::
          {:ok, DeviceProfile.t()} | {:error, Ecto.Changeset.t()}
  def remove_mapping(%DeviceProfile{} = profile, control_id) do
    updated_mappings = Map.delete(profile.mappings, control_id)

    update_profile(profile, %{mappings: updated_mappings})
  end

  @doc """
  Import a device profile from a file (Wave 2 feature).

  Supports TSI, Rekordbox, TouchOSC, and generic MIDI mapping files.

  Returns `{:ok, profile}` on success or `{:error, reason}` on failure.
  """
  @spec import_profile(Path.t(), integer()) ::
          {:ok, DeviceProfile.t()} | {:error, term()}
  def import_profile(_path, _user_id) do
    # Stub for Wave 2 — will use ProfileLoader to parse and create profile
    {:error, :not_implemented}
  end

  @doc """
  Export a device profile to a JSON file.

  The exported file can be shared with other users or imported on different machines.
  """
  @spec export_profile(DeviceProfile.t(), Path.t()) :: :ok | {:error, term()}
  def export_profile(%DeviceProfile{} = profile, path) do
    data = %{
      version: "1.0",
      name: profile.name,
      vendor: profile.vendor,
      source: profile.source,
      device_id: profile.device_id,
      mappings: profile.mappings,
      exported_at: DateTime.utc_now()
    }

    json = Jason.encode!(data, pretty: true)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
