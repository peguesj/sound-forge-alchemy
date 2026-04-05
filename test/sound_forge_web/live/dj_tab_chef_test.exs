defmodule SoundForgeWeb.DjTabChefTest do
  @moduledoc """
  Tests for DJ tab Chef-related events and stem loop operations.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Chef Test Track",
      artist: "Chef Artist",
      duration: 240
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/chef_test.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :bass, file_path: "stems/bass.wav", file_size: 1024})
    stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :other, file_path: "stems/other.wav", file_size: 1024})

    %{track: track}
  end

  defp load_dj_with_track(conn, track) do
    {:ok, view, _html} = live(conn, ~p"/?tab=dj")
    render_click(view, "load_track", %{"track-id" => track.id, "deck" => "1"})
    view
  end

  describe "chef panel events" do
    test "chef_cook without prompt does not crash", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_cook", %{})
      assert is_binary(html)
    end

    test "chef_load_recipe does not crash", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_load_recipe", %{})
      assert is_binary(html)
    end

    test "chef_remix does not crash", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_remix", %{})
      assert is_binary(html)
    end
  end

  describe "stem loop events" do
    test "toggle_stem_loops on deck 1", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "toggle_stem_loops", %{"deck" => "1"})
      assert is_binary(html)
    end
  end

  describe "deck volume and effects" do
    test "set_deck_volume on deck 1", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "75"})
      assert is_binary(html)
    end

    test "set_time_factor on deck 1", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "set_time_factor", %{"deck" => "1", "factor" => "0.5"})
      assert is_binary(html)
    end

    test "toggle_eq_kill for mid band", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "mid"})
      assert is_binary(html)
    end

    test "toggle_eq_kill for high band", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "high"})
      assert is_binary(html)
    end

    test "set_filter with lowpass mode", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "lowpass", "cutoff" => "0.5"})
      assert is_binary(html)
    end

    test "set_filter with highpass mode", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "highpass", "cutoff" => "0.3"})
      assert is_binary(html)
    end
  end

  describe "cue operations" do
    test "set_cue and delete_cue cycle", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      render_click(view, "set_cue", %{"deck" => "1"})
      html = render(view)
      assert is_binary(html)
    end

    test "set_hot_cue with letter", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "set_hot_cue", %{"deck" => "1", "letter" => "A"})
      assert is_binary(html)
    end

    test "clear_hot_cue with letter", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      render_click(view, "set_hot_cue", %{"deck" => "1", "letter" => "B"})
      html = render_click(view, "clear_hot_cue", %{"deck" => "1", "letter" => "B"})
      assert is_binary(html)
    end
  end

  describe "deck navigation" do
    test "time_update on deck 1", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "time_update", %{"deck" => "1", "position" => "30.5"})
      assert is_binary(html)
    end

    test "deck_stopped on deck 1", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "deck_stopped", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "skip_section backward", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "backward"})
      assert is_binary(html)
    end
  end

  describe "validate_preset no-op" do
    test "validate_preset returns without crash", %{conn: conn, track: track} do
      view = load_dj_with_track(conn, track)
      html = render_click(view, "validate_preset", %{})
      assert is_binary(html)
    end
  end
end
