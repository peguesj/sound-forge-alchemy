defmodule SoundForge.DJ.StemLoopTest do
  use SoundForge.DataCase

  alias SoundForge.DJ.StemLoop

  describe "changeset/2" do
    test "valid changeset" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 0,
        end_ms: 5000,
        label: "Intro Loop",
        color: "#FF0000"
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      assert changeset.valid?
    end

    test "requires stem_id, track_id, user_id, start_ms, end_ms" do
      changeset = StemLoop.changeset(%StemLoop{}, %{})
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :stem_id)
      assert Keyword.has_key?(changeset.errors, :track_id)
      assert Keyword.has_key?(changeset.errors, :user_id)
      assert Keyword.has_key?(changeset.errors, :start_ms)
      assert Keyword.has_key?(changeset.errors, :end_ms)
    end

    test "rejects end_ms <= start_ms" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 5000,
        end_ms: 3000
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :end_ms)
    end

    test "rejects equal start and end" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 5000,
        end_ms: 5000
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      refute changeset.valid?
    end

    test "rejects negative start_ms" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: -1,
        end_ms: 5000
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      refute changeset.valid?
    end

    test "rejects invalid color format" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 0,
        end_ms: 5000,
        color: "red"
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :color)
    end

    test "accepts valid hex color" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 0,
        end_ms: 5000,
        color: "#00FF00"
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      assert changeset.valid?
    end

    test "rejects label over 100 chars" do
      attrs = %{
        stem_id: Ecto.UUID.generate(),
        track_id: Ecto.UUID.generate(),
        user_id: 1,
        start_ms: 0,
        end_ms: 5000,
        label: String.duplicate("a", 101)
      }

      changeset = StemLoop.changeset(%StemLoop{}, attrs)
      refute changeset.valid?
    end
  end
end
