defmodule SoundForge.Repo.Migrations.AddTabContextToMidiMappings do
  use Ecto.Migration

  @doc """
  Adds tab_context and preset_name columns to midi_mappings for universal
  cross-tab preset support.

  - tab_context: which UI tab context this mapping is active in
    ("universal", "dj", "daw", "library", "sampler") — nullable, defaults
    to NULL meaning "universal" (active in all contexts).
  - preset_name: groups mappings by preset name (e.g. "mpc_live2_universal"),
    enabling bulk insert/delete of a full controller profile.
  """
  def change do
    alter table(:midi_mappings) do
      add :tab_context, :string, null: true
      add :preset_name, :string, null: true
    end

    create index(:midi_mappings, [:preset_name])
    create index(:midi_mappings, [:tab_context])
  end
end
