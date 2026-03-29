defmodule SoundForge.Repo.Migrations.AddSynthConfigToSamplerPads do
  use Ecto.Migration

  def change do
    alter table(:sampler_pads) do
      add :synth_config, :map
    end
  end
end
