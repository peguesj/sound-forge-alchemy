defmodule SoundForge.MusicExtendedTest do
  @moduledoc """
  Extended Music context tests: filters, sorting, pagination, search, utility functions.
  """
  use SoundForge.DataCase

  alias SoundForge.Music

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "list_tracks/1 filtering" do
    test "filters by artist" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "Song A", artist: "Alpha"})
      track_fixture(%{user_id: user.id, title: "Song B", artist: "Beta"})

      result = Music.list_tracks(filters: %{artist: "Alpha"})
      assert length(result) >= 1
      assert Enum.all?(result, &(&1.artist == "Alpha"))
    end

    test "filters by album" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "Song A", album: "Debut"})
      track_fixture(%{user_id: user.id, title: "Song B", album: "Other"})

      result = Music.list_tracks(filters: %{album: "Debut"})
      assert Enum.all?(result, &(&1.album == "Debut"))
    end

    test "status all returns everything" do
      user = user_fixture()
      track_fixture(%{user_id: user.id})
      result = Music.list_tracks(filters: %{status: "all"})
      assert length(result) >= 1
    end
  end

  describe "list_tracks/1 sorting" do
    test "sorts by title" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "Zebra"})
      track_fixture(%{user_id: user.id, title: "Alpha"})

      result = Music.list_tracks(sort_by: :title)
      titles = Enum.map(result, & &1.title)
      assert titles == Enum.sort(titles)
    end

    test "sorts by artist" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, artist: "ZZ Top"})
      track_fixture(%{user_id: user.id, artist: "ABBA"})

      result = Music.list_tracks(sort_by: :artist)
      artists = Enum.map(result, & &1.artist)
      assert artists == Enum.sort(artists)
    end

    test "sorts by duration desc" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, duration: 100})
      track_fixture(%{user_id: user.id, duration: 300})

      result = Music.list_tracks(sort_by: :duration)
      durations = Enum.map(result, & &1.duration)
      assert hd(durations) >= List.last(durations)
    end

    test "sorts by newest" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "First"})
      track_fixture(%{user_id: user.id, title: "Second"})

      result = Music.list_tracks(sort_by: :newest)
      assert length(result) >= 2
    end

    test "sorts by oldest" do
      user = user_fixture()
      track_fixture(%{user_id: user.id})

      result = Music.list_tracks(sort_by: :oldest)
      assert length(result) >= 1
    end
  end

  describe "list_tracks/1 pagination" do
    test "paginates with per_page" do
      user = user_fixture()
      for i <- 1..5, do: track_fixture(%{user_id: user.id, title: "Track #{i}"})

      page1 = Music.list_tracks(per_page: 2, page: 1)
      page2 = Music.list_tracks(per_page: 2, page: 2)

      assert length(page1) == 2
      assert length(page2) == 2
      refute Enum.any?(page1, fn t -> t.id in Enum.map(page2, & &1.id) end)
    end
  end

  describe "list_tracks/2 with scope" do
    test "scopes to user" do
      user1 = user_fixture()
      user2 = user_fixture()
      scope = SoundForge.Accounts.Scope.for_user(user1)

      track_fixture(%{user_id: user1.id})
      track_fixture(%{user_id: user2.id})

      result = Music.list_tracks(scope)
      assert Enum.all?(result, &(&1.user_id == user1.id))
    end
  end

  describe "search_tracks/1 (no scope)" do
    test "finds tracks by title" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "Unique Search Term XYZ"})

      results = Music.search_tracks("Unique Search Term")
      assert length(results) >= 1
    end

    test "returns empty for blank query" do
      assert Music.search_tracks("") == []
    end

    test "returns empty for nil query" do
      assert Music.search_tracks(nil) == []
    end
  end

  describe "count_tracks/0" do
    test "counts all tracks" do
      count_before = Music.count_tracks()
      user = user_fixture()
      track_fixture(%{user_id: user.id})
      assert Music.count_tracks() == count_before + 1
    end
  end

  describe "list_distinct_artists/1" do
    test "returns unique artists" do
      user = user_fixture()
      scope = SoundForge.Accounts.Scope.for_user(user)
      track_fixture(%{user_id: user.id, artist: "Same"})
      track_fixture(%{user_id: user.id, artist: "Same"})
      track_fixture(%{user_id: user.id, artist: "Other"})

      artists = Music.list_distinct_artists(scope)
      assert length(artists) == 2
      assert "Same" in artists
      assert "Other" in artists
    end
  end

  describe "list_distinct_artists/0" do
    test "returns all distinct artists" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, artist: "GlobalArtist"})
      artists = Music.list_distinct_artists()
      assert "GlobalArtist" in artists
    end
  end

  describe "get_track_by_spotify_id/1" do
    test "finds track by spotify_id" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id, spotify_id: "sp_unique_123"})
      found = Music.get_track_by_spotify_id("sp_unique_123")
      assert found.id == track.id
    end

    test "returns nil for non-existent spotify_id" do
      assert is_nil(Music.get_track_by_spotify_id("nonexistent"))
    end

    test "returns nil for nil input" do
      assert is_nil(Music.get_track_by_spotify_id(nil))
    end
  end

  describe "count_stems/1" do
    test "returns 0 for track with no stems" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      assert Music.count_stems(track.id) == 0
    end

    test "returns correct count with stems" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums})

      assert Music.count_stems(track.id) == 2
    end
  end

  describe "change_track/2" do
    test "returns changeset" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      changeset = Music.change_track(track)
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset with attrs" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      changeset = Music.change_track(track, %{title: "New Title"})
      assert changeset.changes[:title] == "New Title"
    end
  end

  describe "get_track_with_details!/1" do
    test "returns track with preloaded associations" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})

      detailed = Music.get_track_with_details!(track.id)
      assert detailed.id == track.id
      assert is_list(detailed.stems)
      assert is_list(detailed.analysis_results)
      assert is_list(detailed.download_jobs)
    end
  end

  describe "delete_track_with_files/1" do
    test "deletes track and attempts file cleanup" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      assert {:ok, _} = Music.delete_track_with_files(track)
      assert {:ok, nil} = Music.get_track(track.id)
    end
  end
end
