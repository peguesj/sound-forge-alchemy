defmodule SoundForge.Repo.Migrations.AddPadSequencesToSamplerBanks do
  use Ecto.Migration

  def change do
    alter table(:sampler_banks) do
      add :pad_sequences, :map
    end
  end
end
