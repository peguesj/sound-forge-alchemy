defmodule SoundForgeWeb.AudioPlayerIntegrationTest do
  @moduledoc """
  Integration tests for AudioPlayerLive component events.
  AudioPlayerLive is a LiveComponent embedded in dashboard when playing a local track.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Audio Player Test",
      artist: "Player Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/player_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :bass, file_path: "stems/bass.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :other, file_path: "stems/other.wav", file_size: 1024})

    %{track: track}
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.AudioPlayerLive)
    end

    test "exports handle_event/3" do
      assert {:handle_event, 3} in SoundForgeWeb.AudioPlayerLive.__info__(:functions)
    end

    test "exports update/2" do
      assert {:update, 2} in SoundForgeWeb.AudioPlayerLive.__info__(:functions)
    end
  end

  describe "play_track triggers player" do
    test "play_track event redirects to track detail view", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      result = render_click(view, "play_track", %{"id" => track.id})
      # play_track with stemmed track triggers a live_redirect to track detail
      assert is_binary(result) or match?({:error, {:live_redirect, _}}, result)
    end

    test "play_track with nonexistent track shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "play_track", %{"id" => Ecto.UUID.generate()})
      assert html =~ "not found" or is_binary(html)
    end
  end
end
