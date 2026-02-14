defmodule SoundForge.Music.PlaylistTrackTest do
  use SoundForge.DataCase, async: true

  alias SoundForge.Music.PlaylistTrack

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        PlaylistTrack.changeset(%PlaylistTrack{}, %{
          playlist_id: Ecto.UUID.generate(),
          track_id: Ecto.UUID.generate(),
          position: 1
        })

      assert changeset.valid?
    end

    test "requires playlist_id" do
      changeset =
        PlaylistTrack.changeset(%PlaylistTrack{}, %{
          track_id: Ecto.UUID.generate()
        })

      assert %{playlist_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires track_id" do
      changeset =
        PlaylistTrack.changeset(%PlaylistTrack{}, %{
          playlist_id: Ecto.UUID.generate()
        })

      assert %{track_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "position is optional" do
      changeset =
        PlaylistTrack.changeset(%PlaylistTrack{}, %{
          playlist_id: Ecto.UUID.generate(),
          track_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "accepts integer position" do
      changeset =
        PlaylistTrack.changeset(%PlaylistTrack{}, %{
          playlist_id: Ecto.UUID.generate(),
          track_id: Ecto.UUID.generate(),
          position: 5
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :position) == 5
    end
  end
end
