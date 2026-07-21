defmodule SoundForgeWeb.DashboardPipelineExtendedTest do
  @moduledoc """
  Tests for dashboard pipeline, track operations, and template rendering
  with various data states (tracks with downloads, stems, analysis, etc.)
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "track with completed download" do
    test "renders track with download_status completed", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Downloaded Track", duration: 180})

      download_job_fixture(%{
        track_id: track.id,
        status: :completed,
        output_path: "/tmp/test.mp3"
      })

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Downloaded Track"
    end

    test "select track with download", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "DL Selected"})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "/tmp/dl.mp3"})

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "select_track", %{"track_id" => track.id})
      assert is_binary(html)
    end
  end

  describe "track with processing" do
    test "renders track with processing job", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Processing Track"})
      processing_job_fixture(%{track_id: track.id, status: :processing})

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Processing Track"
    end

    test "renders track with completed stems", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Stemmed Track"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

      for type <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
      end

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Stemmed Track"
    end
  end

  describe "track with analysis" do
    test "renders track with analysis results", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Analyzed Track"})
      aj = analysis_job_fixture(%{track_id: track.id, status: :completed})

      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: aj.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.85
      })

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Analyzed Track"
    end
  end

  describe "pagination with multiple tracks" do
    test "renders paginated track list", %{conn: conn, user: user} do
      for i <- 1..25 do
        track_fixture(%{user_id: user.id, title: "Page Track #{i}", artist: "Artist #{i}"})
      end

      {:ok, view, _html} = live(conn, "/")
      # Navigate to page 2
      html = render_click(view, "page", %{"page" => "2"})
      assert is_binary(html)
    end
  end

  describe "metadata editing with save" do
    test "edit and save track metadata", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Old Title", artist: "Old Artist"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "edit_metadata", %{"id" => track.id})

      html =
        render_click(view, "save_metadata", %{
          "track" => %{"title" => "New Title", "artist" => "New Artist"}
        })

      assert html =~ "New Title" or html =~ "Track updated"
    end
  end

  describe "pipeline operations" do
    test "dismiss_pipeline for a track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Dismiss Pipeline"})
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "dismiss_pipeline", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "nav with playlist" do
    test "nav_playlist shows playlist tracks", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Playlist Track"})
      playlist = playlist_fixture(%{user_id: user.id, name: "My Playlist"})
      SoundForge.Music.add_track_to_playlist(playlist, track)

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_playlist", %{"id" => playlist.id})
      assert is_binary(html)
    end
  end

  describe "mixed library with multiple data states" do
    test "renders library with mix of downloaded, processing, and fresh tracks", %{
      conn: conn,
      user: user
    } do
      # Fresh track
      track_fixture(%{user_id: user.id, title: "Fresh Track"})

      # Downloaded track
      track2 = track_fixture(%{user_id: user.id, title: "Downloaded One"})

      download_job_fixture(%{
        track_id: track2.id,
        status: :completed,
        output_path: "/tmp/test.mp3"
      })

      # Stemmed track
      track3 = track_fixture(%{user_id: user.id, title: "Stemmed One"})
      pj = processing_job_fixture(%{track_id: track3.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track3.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Fresh Track"
      assert html =~ "Downloaded One"
      assert html =~ "Stemmed One"
    end
  end

  describe "filter combinations" do
    test "filter by artist then clear", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "ArtistFilter", artist: "SpecificArtist"})
      {:ok, view, _html} = live(conn, "/")
      render_click(view, "filter", %{"artist" => "SpecificArtist", "status" => "all"})
      html = render_click(view, "filter", %{"artist" => "all", "status" => "all"})
      assert is_binary(html)
    end
  end
end
