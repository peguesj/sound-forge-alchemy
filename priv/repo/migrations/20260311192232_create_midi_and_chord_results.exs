defmodule SoundForge.Repo.Migrations.CreateMidiAndChordResults do
  use Ecto.Migration

  def change do
    create table(:midi_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :notes, {:array, :map}, null: false, default: []
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:midi_results, [:track_id])

    create table(:chord_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chords, {:array, :map}, null: false, default: []
      add :key, :string
      add :track_id, references(:tracks, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chord_results, [:track_id])
  end
end
