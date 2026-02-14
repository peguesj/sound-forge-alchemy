defmodule SoundForge.Music.PlaylistTest do
  use SoundForge.DataCase

  alias SoundForge.Music
  alias SoundForge.Music.Playlist

  import SoundForge.MusicFixtures
  import SoundForge.AccountsFixtures

  setup do
    user1 = user_fixture()
    user2 = user_fixture()
    %{user1: user1, user2: user2}
  end

  describe "create_playlist/1" do
    test "with valid data creates a playlist", %{user1: user1} do
      valid_attrs = %{
        name: "My Playlist",
        description: "Some great songs",
        spotify_id: "sp_123",
        spotify_url: "https://open.spotify.com/playlist/sp_123",
        cover_art_url: "https://example.com/cover.jpg",
        user_id: user1.id
      }

      assert {:ok, %Playlist{} = playlist} = Music.create_playlist(valid_attrs)
      assert playlist.name == "My Playlist"
      assert playlist.description == "Some great songs"
      assert playlist.spotify_id == "sp_123"
      assert playlist.spotify_url == "https://open.spotify.com/playlist/sp_123"
      assert playlist.cover_art_url == "https://example.com/cover.jpg"
      assert playlist.user_id == user1.id
    end

    test "with missing name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Music.create_playlist(%{name: nil})
    end

    test "with empty name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Music.create_playlist(%{name: ""})
    end
  end

  describe "list_playlists/1" do
    test "returns playlists for the given user ordered by name", %{user1: user1, user2: user2} do
      playlist_fixture(%{name: "Zebra Mix", user_id: user1.id})
      playlist_fixture(%{name: "Alpha Mix", user_id: user1.id})
      playlist_fixture(%{name: "Other User Mix", user_id: user2.id})

      scope = %{user: %{id: user1.id}}
      playlists = Music.list_playlists(scope)

      assert length(playlists) == 2
      assert [first, second] = playlists
      assert first.name == "Alpha Mix"
      assert second.name == "Zebra Mix"
    end

    test "returns empty list when user has no playlists" do
      scope = %{user: %{id: 999}}
      assert Music.list_playlists(scope) == []
    end
  end

  describe "add_track_to_playlist/3" do
    test "adds a track to a playlist", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})

      assert {:ok, playlist_track} = Music.add_track_to_playlist(playlist, track, 1)
      assert playlist_track.playlist_id == playlist.id
      assert playlist_track.track_id == track.id
      assert playlist_track.position == 1
    end

    test "adding same track twice does not error with on_conflict: :nothing", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})

      assert {:ok, _} = Music.add_track_to_playlist(playlist, track, 1)
      # Second insert should not raise due to on_conflict: :nothing
      assert {:ok, _} = Music.add_track_to_playlist(playlist, track, 2)
    end
  end

  describe "remove_track_from_playlist/2" do
    test "removes a track from a playlist", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})

      {:ok, _} = Music.add_track_to_playlist(playlist, track, 1)
      assert {1, nil} = Music.remove_track_from_playlist(playlist, track)

      # Verify track is no longer in the playlist
      assert Music.list_tracks_for_playlist(playlist.id) == []
    end

    test "returns {0, nil} when track is not in the playlist", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})

      assert {0, nil} = Music.remove_track_from_playlist(playlist, track)
    end
  end

  describe "list_tracks_for_playlist/2" do
    test "returns tracks ordered by position", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track1 = track_fixture(%{title: "Track One", user_id: user1.id})
      track2 = track_fixture(%{title: "Track Two", user_id: user1.id})
      track3 = track_fixture(%{title: "Track Three", user_id: user1.id})

      {:ok, _} = Music.add_track_to_playlist(playlist, track3, 3)
      {:ok, _} = Music.add_track_to_playlist(playlist, track1, 1)
      {:ok, _} = Music.add_track_to_playlist(playlist, track2, 2)

      tracks = Music.list_tracks_for_playlist(playlist.id)
      assert length(tracks) == 3
      assert [first, second, third] = tracks
      assert first.id == track1.id
      assert second.id == track2.id
      assert third.id == track3.id
    end

    test "returns empty list for a playlist with no tracks", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      assert Music.list_tracks_for_playlist(playlist.id) == []
    end
  end

  describe "list_distinct_albums/1" do
    test "returns unique album names for a user", %{user1: user1, user2: user2} do
      track_fixture(%{title: "Song 1", album: "Album B", user_id: user1.id})
      track_fixture(%{title: "Song 2", album: "Album A", user_id: user1.id})
      track_fixture(%{title: "Song 3", album: "Album B", user_id: user1.id})
      track_fixture(%{title: "Song 4", album: "Album C", user_id: user2.id})

      scope = %{user: %{id: user1.id}}
      albums = Music.list_distinct_albums(scope)

      assert length(albums) == 2
      assert albums == ["Album A", "Album B"]
    end

    test "excludes nil and empty album names", %{user1: user1} do
      track_fixture(%{title: "Song 1", album: "Real Album", user_id: user1.id})
      track_fixture(%{title: "Song 2", album: nil, user_id: user1.id})
      track_fixture(%{title: "Song 3", album: "", user_id: user1.id})

      scope = %{user: %{id: user1.id}}
      albums = Music.list_distinct_albums(scope)

      assert albums == ["Real Album"]
    end

    test "returns empty list when user has no tracks" do
      scope = %{user: %{id: 999}}
      assert Music.list_distinct_albums(scope) == []
    end
  end

  describe "get_playlist!/1" do
    test "returns playlist with preloaded tracks", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})
      {:ok, _} = Music.add_track_to_playlist(playlist, track, 1)

      fetched = Music.get_playlist!(playlist.id)
      assert fetched.id == playlist.id
      assert length(fetched.playlist_tracks) == 1
      assert hd(fetched.playlist_tracks).track.id == track.id
    end

    test "raises Ecto.NoResultsError for nonexistent id" do
      assert_raise Ecto.NoResultsError, fn ->
        Music.get_playlist!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_playlist_by_spotify_id/2" do
    test "returns playlist matching spotify_id and user_id", %{user1: user1} do
      playlist = playlist_fixture(%{spotify_id: "sp_find_me", user_id: user1.id})
      assert found = Music.get_playlist_by_spotify_id("sp_find_me", user1.id)
      assert found.id == playlist.id
    end

    test "returns nil for non-matching spotify_id" do
      assert Music.get_playlist_by_spotify_id("nonexistent", 1) == nil
    end

    test "returns nil for nil spotify_id" do
      assert Music.get_playlist_by_spotify_id(nil, 1) == nil
    end
  end

  describe "update_playlist/2" do
    test "updates playlist attributes", %{user1: user1} do
      playlist = playlist_fixture(%{name: "Original", user_id: user1.id})
      assert {:ok, updated} = Music.update_playlist(playlist, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "returns error changeset for invalid data", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      assert {:error, %Ecto.Changeset{}} = Music.update_playlist(playlist, %{name: nil})
    end
  end

  describe "delete_playlist/1" do
    test "deletes the playlist", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      assert {:ok, %Playlist{}} = Music.delete_playlist(playlist)

      assert_raise Ecto.NoResultsError, fn ->
        Music.get_playlist!(playlist.id)
      end
    end

    test "cascade deletes associated playlist_tracks", %{user1: user1} do
      playlist = playlist_fixture(%{user_id: user1.id})
      track = track_fixture(%{user_id: user1.id})
      {:ok, _} = Music.add_track_to_playlist(playlist, track, 1)

      assert {:ok, _} = Music.delete_playlist(playlist)

      # Track should still exist, but playlist_track should be gone
      assert Music.get_track!(track.id).id == track.id
    end
  end
end
