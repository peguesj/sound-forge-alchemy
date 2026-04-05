defmodule SoundForge.Music.TrackTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.Track

  @valid_attrs %{
    title: "Bohemian Rhapsody",
    artist: "Queen",
    album: "A Night at the Opera",
    duration: 354,
    spotify_id: "3z8h0TU7ReDPLIbE0lXSzR"
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = Track.changeset(%Track{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires title" do
      changeset = Track.changeset(%Track{}, Map.delete(@valid_attrs, :title))
      refute changeset.valid?
    end

    test "validates title min length" do
      changeset = Track.changeset(%Track{}, %{@valid_attrs | title: ""})
      refute changeset.valid?
    end

    test "validates title max length" do
      long = String.duplicate("a", 501)
      changeset = Track.changeset(%Track{}, %{@valid_attrs | title: long})
      refute changeset.valid?

      ok = String.duplicate("a", 500)
      changeset = Track.changeset(%Track{}, %{@valid_attrs | title: ok})
      assert changeset.valid?
    end

    test "validates duration must be positive" do
      zero = Track.changeset(%Track{}, %{@valid_attrs | duration: 0})
      refute zero.valid?

      negative = Track.changeset(%Track{}, %{@valid_attrs | duration: -10})
      refute negative.valid?

      valid = Track.changeset(%Track{}, %{@valid_attrs | duration: 1})
      assert valid.valid?
    end

    test "artist is optional" do
      changeset = Track.changeset(%Track{}, Map.delete(@valid_attrs, :artist))
      assert changeset.valid?
    end

    test "album is optional" do
      changeset = Track.changeset(%Track{}, Map.delete(@valid_attrs, :album))
      assert changeset.valid?
    end

    test "spotify_id is optional" do
      changeset = Track.changeset(%Track{}, Map.delete(@valid_attrs, :spotify_id))
      assert changeset.valid?
    end

    test "duration is optional" do
      changeset = Track.changeset(%Track{}, Map.delete(@valid_attrs, :duration))
      assert changeset.valid?
    end

    test "user_id is optional" do
      changeset = Track.changeset(%Track{}, @valid_attrs)
      assert changeset.valid?
      assert is_nil(Ecto.Changeset.get_field(changeset, :user_id))
    end

    test "download_status is virtual" do
      track = %Track{}
      assert is_nil(track.download_status)
    end
  end
end
