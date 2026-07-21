defmodule SoundForge.Music.StemTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.Stem

  @valid_attrs %{
    processing_job_id: Ecto.UUID.generate(),
    track_id: Ecto.UUID.generate(),
    stem_type: :vocals,
    file_path: "/path/to/vocals.wav",
    file_size: 1_048_576
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = Stem.changeset(%Stem{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires processing_job_id" do
      changeset = Stem.changeset(%Stem{}, Map.delete(@valid_attrs, :processing_job_id))
      refute changeset.valid?
    end

    test "requires track_id" do
      changeset = Stem.changeset(%Stem{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "requires stem_type" do
      changeset = Stem.changeset(%Stem{}, Map.delete(@valid_attrs, :stem_type))
      refute changeset.valid?
    end

    test "validates all stem types" do
      stem_types = [
        :vocals,
        :drums,
        :bass,
        :other,
        :guitar,
        :piano,
        :electric_guitar,
        :acoustic_guitar,
        :synth,
        :strings,
        :wind
      ]

      for type <- stem_types do
        changeset = Stem.changeset(%Stem{}, %{@valid_attrs | stem_type: type})
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "file_path and file_size are optional" do
      changeset = Stem.changeset(%Stem{}, Map.drop(@valid_attrs, [:file_path, :file_size]))
      assert changeset.valid?
    end

    test "options defaults to empty map" do
      stem = %Stem{}
      assert stem.options == %{}
    end

    test "source defaults to local" do
      stem = %Stem{}
      assert stem.source == "local"
    end
  end

  describe "export_changeset/2" do
    test "does not require processing_job_id" do
      attrs = Map.delete(@valid_attrs, :processing_job_id)
      changeset = Stem.export_changeset(%Stem{}, attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      attrs = Map.drop(@valid_attrs, [:processing_job_id, :track_id])
      changeset = Stem.export_changeset(%Stem{}, attrs)
      refute changeset.valid?
    end

    test "requires stem_type" do
      attrs = Map.drop(@valid_attrs, [:processing_job_id, :stem_type])
      changeset = Stem.export_changeset(%Stem{}, attrs)
      refute changeset.valid?
    end

    test "validates stem_type inclusion" do
      attrs = %{track_id: Ecto.UUID.generate(), stem_type: :vocals}
      changeset = Stem.export_changeset(%Stem{}, attrs)
      assert changeset.valid?
    end
  end
end
