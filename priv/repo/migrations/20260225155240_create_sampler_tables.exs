defmodule SoundForge.Repo.Migrations.CreateSamplerTables do
  use Ecto.Migration

  def change do
    create table(:sampler_banks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, default: "Bank A"
      add :color, :string, default: "#8b5cf6"
      add :position, :integer, null: false, default: 0
      add :user_id, :integer, null: false
      add :bpm, :float

      timestamps(type: :utc_datetime)
    end

    create index(:sampler_banks, [:user_id])

    create table(:sampler_pads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :index, :integer, null: false
      add :label, :string
      add :color, :string, default: "#6b7280"
      add :volume, :float, default: 1.0
      add :pitch, :float, default: 0.0
      add :velocity, :float, default: 1.0
      add :start_time, :float, default: 0.0
      add :end_time, :float
      add :bank_id, references(:sampler_banks, type: :binary_id, on_delete: :delete_all), null: false
      add :stem_id, references(:stems, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:sampler_pads, [:bank_id])
    create index(:sampler_pads, [:stem_id])
    create unique_index(:sampler_pads, [:bank_id, :index])
  end
end
