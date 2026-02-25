defmodule SoundForge.Repo.Migrations.AddPadActionsToMidiMappings do
  use Ecto.Migration

  @doc """
  Adds bank_id column to midi_mappings for bank-scoped MIDI Learn mappings.
  The new pad-specific actions (pad_trigger, pad_volume, pad_pitch,
  pad_velocity, pad_master_volume) are handled by the Ecto.Enum in the
  Mapping schema -- they don't require a database-level enum change since
  the action column stores strings.
  """
  def change do
    alter table(:midi_mappings) do
      add :bank_id, references(:sampler_banks, type: :binary_id, on_delete: :delete_all),
        null: true

      add :parameter_index, :integer, null: true
    end

    create index(:midi_mappings, [:bank_id])
  end
end
