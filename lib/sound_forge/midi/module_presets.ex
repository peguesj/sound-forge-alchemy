defmodule SoundForge.MIDI.ModulePresets do
  @moduledoc """
  Context for managing per-module MIDI presets.
  """

  import Ecto.Query

  alias SoundForge.Repo
  alias SoundForge.MIDI.ModulePreset

  @doc "List all presets for a user, optionally filtered by module."
  def list_presets(user_id, module \\ nil) do
    ModulePreset
    |> where([p], p.user_id == ^user_id)
    |> maybe_filter_module(module)
    |> order_by([p], [desc: p.is_default, asc: p.name])
    |> Repo.all()
  end

  @doc "Get preset by id."
  def get_preset(id), do: Repo.get(ModulePreset, id)

  @doc "Get the default preset for a user/module."
  def get_default_preset(user_id, module) do
    ModulePreset
    |> where([p], p.user_id == ^user_id and p.module == ^module and p.is_default == true)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Create a preset."
  def create_preset(attrs) do
    %ModulePreset{}
    |> ModulePreset.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a preset."
  def update_preset(%ModulePreset{} = preset, attrs) do
    preset
    |> ModulePreset.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a preset."
  def delete_preset(%ModulePreset{} = preset), do: Repo.delete(preset)

  @doc "Set a preset as the default for its module (clears other defaults)."
  def set_default(user_id, preset_id) do
    Repo.transaction(fn ->
      case Repo.get(ModulePreset, preset_id) do
        %ModulePreset{user_id: ^user_id} = preset ->
          ModulePreset
          |> where([p], p.user_id == ^user_id and p.module == ^preset.module)
          |> Repo.update_all(set: [is_default: false])

          preset
          |> ModulePreset.changeset(%{is_default: true})
          |> Repo.update!()

        _ ->
          Repo.rollback(:not_found)
      end
    end)
  end

  @doc """
  Upsert a preset from a parsed TSI/Serato/RekordBox import.
  Returns {:ok, preset} or {:error, changeset}.
  """
  def upsert_imported_preset(user_id, module, name, mappings, layout_metadata, source) do
    case Repo.get_by(ModulePreset, user_id: user_id, module: module, name: name) do
      nil ->
        create_preset(%{
          user_id: user_id,
          module: module,
          name: name,
          source: source,
          mappings: mappings,
          layout_metadata: layout_metadata
        })

      existing ->
        update_preset(existing, %{mappings: mappings, layout_metadata: layout_metadata, source: source})
    end
  end

  defp maybe_filter_module(query, nil), do: query
  defp maybe_filter_module(query, module), do: where(query, [p], p.module == ^module)
end
