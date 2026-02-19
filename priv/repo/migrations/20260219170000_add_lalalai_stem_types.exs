defmodule SoundForge.Repo.Migrations.AddLalalaiStemTypes do
  use Ecto.Migration

  @doc """
  Adds lalal.ai-specific stem types to the stems table.

  The stems table uses a varchar column for stem_type (Ecto.Enum with string backing).
  This migration is a no-op at the DB level since Ecto.Enum with :string type
  stores atoms as strings without a DB-level enum constraint.

  The constraint is enforced at the application layer via Ecto changeset validation.
  This migration documents the expansion of supported values.
  """
  def change do
    # The stem_type column is a :string (varchar) field backed by Ecto.Enum.
    # No DB-level enum type exists, so no ALTER TYPE command is needed.
    # The new values (electric_guitar, acoustic_guitar, synth, strings, wind)
    # are supported by updating the Ecto.Enum definition in the schema.
    #
    # We add a comment to document the supported values.
    execute(
      "COMMENT ON COLUMN stems.stem_type IS 'Supported: vocals, drums, bass, other, guitar, piano, electric_guitar, acoustic_guitar, synth, strings, wind'",
      "COMMENT ON COLUMN stems.stem_type IS 'Supported: vocals, drums, bass, other, guitar, piano'"
    )
  end
end
