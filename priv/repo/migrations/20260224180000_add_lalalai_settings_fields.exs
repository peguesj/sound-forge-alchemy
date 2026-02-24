defmodule SoundForge.Repo.Migrations.AddLalalaiSettingsFields do
  use Ecto.Migration

  def change do
    alter table(:user_settings) do
      add :lalalai_splitter, :string, default: "phoenix"
      add :lalalai_dereverb, :boolean, default: false
      add :lalalai_extraction_level, :string, default: "clear_cut"
      add :lalalai_output_format, :string
    end
  end
end
