defmodule SoundForge.Repo.Migrations.AddMidiBarPositionToUserSettings do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add_if_not_exists :midi_bar_position, :string, default: "bottom"
      add_if_not_exists :midi_bar_visible, :boolean, default: true
    end
  end
end
