defmodule SoundForge.Repo.Migrations.AddAutoMidiChordSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :auto_midi_conversion, :boolean, default: false
      add :auto_chord_detection, :boolean, default: false
    end
  end
end
