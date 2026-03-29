defmodule SoundForge.Repo.Migrations.CreateMidiNoteEdits do
  use Ecto.Migration

  def change do
    create table(:midi_note_edits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :note, :integer, null: false
      add :onset_sec, :float, null: false
      add :duration_sec, :float, null: false, default: 0.25
      add :velocity, :float, null: false, default: 0.8
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:midi_note_edits, [:track_id, :user_id])
  end
end
