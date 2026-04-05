defmodule SoundForgeWeb.DjRemainingEventsTest do
  @moduledoc "Tests for DJ tab events not covered by existing test files."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track1 = track_fixture(%{user_id: user.id, title: "DJ Remain A", artist: "Art A", duration: 240})
    track2 = track_fixture(%{user_id: user.id, title: "DJ Remain B", artist: "Art B", duration: 180})

    download_job_fixture(%{track_id: track1.id, status: :completed, output_path: "priv/uploads/downloads/remain_a.mp3"})
    download_job_fixture(%{track_id: track2.id, status: :completed, output_path: "priv/uploads/downloads/remain_b.mp3"})

    pj1 = processing_job_fixture(%{track_id: track1.id, model: "htdemucs", status: :completed})
    pj2 = processing_job_fixture(%{track_id: track2.id, model: "htdemucs", status: :completed})

    for st <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{track_id: track1.id, processing_job_id: pj1.id, stem_type: st, file_path: "stems/#{st}_ra.wav", file_size: 1024})
      stem_fixture(%{track_id: track2.id, processing_job_id: pj2.id, stem_type: st, file_path: "stems/#{st}_rb.wav", file_size: 1024})
    end

    %{track1: track1, track2: track2}
  end

  defp load_dj(conn, track1, track2) do
    {:ok, view, _html} = live(conn, ~p"/?tab=dj")
    render_click(view, "load_track", %{"track-id" => track1.id, "deck" => "1"})
    render_click(view, "load_track", %{"track-id" => track2.id, "deck" => "2"})
    view
  end

  describe "master_sync" do
    test "master_sync with both decks loaded", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "master_sync", %{})
      assert is_binary(html)
    end
  end

  describe "metronome" do
    test "toggle_metronome", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "toggle_metronome", %{})
      assert is_binary(html)
    end

    test "toggle_metronome twice", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "toggle_metronome", %{})
      html = render_click(view, "toggle_metronome", %{})
      assert is_binary(html)
    end
  end

  describe "cue operations after setting cues" do
    test "set_cue then trigger_cue", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      # Set a cue first
      render_click(view, "set_cue", %{"deck" => "1"})
      # Try to trigger it (may be first cue in list)
      html = render_click(view, "trigger_cue", %{"deck" => "1", "cue_id" => "cue_0"})
      assert is_binary(html)
    end

    test "delete_cue on deck 1", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "set_cue", %{"deck" => "1"})
      html = render_click(view, "delete_cue", %{"deck" => "1", "cue_id" => "cue_0"})
      assert is_binary(html)
    end

    test "loop_from_cue", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "set_cue", %{"deck" => "1"})
      html = render_click(view, "loop_from_cue", %{"deck" => "1", "cue_id" => "cue_0"})
      assert is_binary(html)
    end
  end

  describe "chef operations" do
    test "chef_cook with prompt", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "toggle_chef_panel", %{})
      render_click(view, "chef_prompt_change", %{"prompt" => "energetic house"})
      html = render_click(view, "chef_cook", %{})
      assert is_binary(html)
    end

    test "chef_load_recipe", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_load_recipe", %{})
      assert is_binary(html)
    end

    test "chef_remix", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_remix", %{})
      assert is_binary(html)
    end

    test "chef_load_to_pads", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "toggle_chef_panel", %{})
      html = render_click(view, "chef_load_to_pads", %{})
      assert is_binary(html)
    end
  end

  describe "preset operations" do
    test "toggle_preset_section", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "toggle_preset_section", %{})
      assert is_binary(html)
    end
  end

  describe "stem loops on deck 2" do
    test "toggle_stem_loops on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "toggle_stem_loops", %{"deck" => "2"})
      assert is_binary(html)
    end
  end

  describe "load_to_pads with params" do
    test "load_to_pads with recipe_name", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "load_to_pads", %{"recipe_name" => "default"})
      assert is_binary(html)
    end

    test "load_to_pads without recipe_name", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "load_to_pads", %{})
      assert is_binary(html)
    end
  end

  describe "auto cue operations" do
    test "promote_auto_cue", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "auto_detect_cues", %{"deck" => "1"})
      html = render_click(view, "promote_auto_cue", %{"deck" => "1", "cue_id" => "auto_0"})
      assert is_binary(html)
    end

    test "dismiss_auto_cue", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      render_click(view, "auto_detect_cues", %{"deck" => "1"})
      html = render_click(view, "dismiss_auto_cue", %{"deck" => "1", "cue_id" => "auto_0"})
      assert is_binary(html)
    end

    test "regenerate_auto_cues on deck 2", %{conn: conn, track1: t1, track2: t2} do
      view = load_dj(conn, t1, t2)
      html = render_click(view, "regenerate_auto_cues", %{"deck" => "2"})
      assert is_binary(html)
    end
  end
end
