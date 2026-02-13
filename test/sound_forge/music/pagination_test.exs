defmodule SoundForge.Music.PaginationTest do
  use SoundForge.DataCase

  alias SoundForge.Music

  import SoundForge.MusicFixtures

  describe "list_tracks with pagination" do
    test "returns all tracks when no pagination opts" do
      for i <- 1..5, do: track_fixture(%{title: "Track #{i}"})
      assert length(Music.list_tracks()) == 5
    end

    test "limits results with per_page" do
      for i <- 1..5, do: track_fixture(%{title: "Track #{i}"})
      assert length(Music.list_tracks(per_page: 2)) == 2
    end

    test "offsets results with page" do
      for i <- 1..5, do: track_fixture(%{title: "Track #{i}"})
      page1 = Music.list_tracks(per_page: 2, page: 1, sort_by: :title)
      page2 = Music.list_tracks(per_page: 2, page: 2, sort_by: :title)
      page3 = Music.list_tracks(per_page: 2, page: 3, sort_by: :title)

      assert length(page1) == 2
      assert length(page2) == 2
      assert length(page3) == 1

      all_ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(Enum.uniq(all_ids)) == 5
    end

    test "returns empty list for page beyond results" do
      track_fixture(%{title: "Only Track"})
      assert Music.list_tracks(per_page: 10, page: 5) == []
    end
  end

  describe "count_tracks" do
    test "returns total track count" do
      assert Music.count_tracks() == 0
      for _ <- 1..3, do: track_fixture()
      assert Music.count_tracks() == 3
    end
  end
end
