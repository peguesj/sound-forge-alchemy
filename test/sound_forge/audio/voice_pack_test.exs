defmodule SoundForge.Audio.VoicePackTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.VoicePack

  @valid_attrs %{
    pack_id: "builtin_male_1",
    name: "Deep Male Voice"
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = VoicePack.changeset(%VoicePack{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires pack_id" do
      changeset = VoicePack.changeset(%VoicePack{}, Map.delete(@valid_attrs, :pack_id))
      refute changeset.valid?
    end

    test "requires name" do
      changeset = VoicePack.changeset(%VoicePack{}, Map.delete(@valid_attrs, :name))
      refute changeset.valid?
    end

    test "accepts optional datetime fields" do
      changeset =
        VoicePack.changeset(%VoicePack{}, Map.merge(@valid_attrs, %{
          created_at_remote: DateTime.utc_now(),
          cached_at: DateTime.utc_now()
        }))

      assert changeset.valid?
    end
  end
end
