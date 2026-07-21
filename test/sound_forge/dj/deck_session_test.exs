defmodule SoundForge.DJ.DeckSessionTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.DeckSession

  @valid_attrs %{
    deck_number: 1,
    user_id: 1
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = DeckSession.changeset(%DeckSession{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires deck_number" do
      changeset = DeckSession.changeset(%DeckSession{}, Map.delete(@valid_attrs, :deck_number))
      refute changeset.valid?
    end

    test "requires user_id" do
      changeset = DeckSession.changeset(%DeckSession{}, Map.delete(@valid_attrs, :user_id))
      refute changeset.valid?
    end

    test "validates deck_number inclusion (1 or 2)" do
      for n <- [1, 2] do
        changeset = DeckSession.changeset(%DeckSession{}, %{@valid_attrs | deck_number: n})
        assert changeset.valid?, "Expected deck_number #{n} to be valid"
      end

      for n <- [0, 3, -1] do
        changeset = DeckSession.changeset(%DeckSession{}, %{@valid_attrs | deck_number: n})
        refute changeset.valid?, "Expected deck_number #{n} to be invalid"
      end
    end

    test "validates pitch_adjust range -8.0 to 8.0" do
      valid = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :pitch_adjust, 4.0))
      assert valid.valid?

      too_low = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :pitch_adjust, -8.1))
      refute too_low.valid?

      too_high = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :pitch_adjust, 8.1))
      refute too_high.valid?

      edge_low = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :pitch_adjust, -8.0))
      assert edge_low.valid?

      edge_high = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :pitch_adjust, 8.0))
      assert edge_high.valid?
    end

    test "validates tempo_bpm must be positive" do
      valid = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :tempo_bpm, 128.0))
      assert valid.valid?

      zero = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :tempo_bpm, 0.0))
      refute zero.valid?

      negative = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :tempo_bpm, -10.0))
      refute negative.valid?
    end

    test "validates loop_start_ms non-negative" do
      valid = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :loop_start_ms, 0))
      assert valid.valid?

      negative = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :loop_start_ms, -1))
      refute negative.valid?
    end

    test "validates loop_end_ms non-negative" do
      valid = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :loop_end_ms, 1000))
      assert valid.valid?

      negative = DeckSession.changeset(%DeckSession{}, Map.put(@valid_attrs, :loop_end_ms, -1))
      refute negative.valid?
    end

    test "validates loop_end_ms must be greater than loop_start_ms" do
      invalid =
        DeckSession.changeset(
          %DeckSession{},
          Map.merge(@valid_attrs, %{loop_start_ms: 1000, loop_end_ms: 500})
        )

      refute invalid.valid?

      equal =
        DeckSession.changeset(
          %DeckSession{},
          Map.merge(@valid_attrs, %{loop_start_ms: 1000, loop_end_ms: 1000})
        )

      refute equal.valid?

      valid =
        DeckSession.changeset(
          %DeckSession{},
          Map.merge(@valid_attrs, %{loop_start_ms: 1000, loop_end_ms: 2000})
        )

      assert valid.valid?
    end

    test "allows nil loop bounds" do
      changeset = DeckSession.changeset(%DeckSession{}, @valid_attrs)
      assert changeset.valid?
      assert is_nil(Ecto.Changeset.get_field(changeset, :loop_start_ms))
      assert is_nil(Ecto.Changeset.get_field(changeset, :loop_end_ms))
    end

    test "pitch_adjust defaults to 0.0" do
      ds = %DeckSession{}
      assert ds.pitch_adjust == 0.0
    end

    test "track_id is optional" do
      changeset = DeckSession.changeset(%DeckSession{}, @valid_attrs)
      assert changeset.valid?
      assert is_nil(Ecto.Changeset.get_field(changeset, :track_id))
    end
  end
end
