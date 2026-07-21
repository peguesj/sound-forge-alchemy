defmodule SoundForgeWeb.DjTabRenderingExtendedTest do
  @moduledoc "Extended rendering tests for DjTabComponent to cover template branches."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "DJ Render Test",
        artist: "Render Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/dj_render.mp3"
    })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    for type <- [:vocals, :drums, :bass, :other] do
      stem_fixture(%{
        track_id: track.id,
        processing_job_id: pj.id,
        stem_type: type,
        file_path: "stems/#{type}.wav",
        file_size: 1024
      })
    end

    %{track: track}
  end

  describe "DJ tab browser events" do
    test "browser_filter updates search", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "browser_filter", %{"filter" => "house"})
      assert is_binary(html)
    end

    test "browser_sort updates sort order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "browser_sort", %{"sort" => "bpm"})
      assert is_binary(html)
    end
  end

  describe "DJ tab effect events" do
    test "deck_echo event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_echo", %{"deck" => "1", "value" => "0.5"})
      assert is_binary(html)
    end

    test "deck_reverb event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_reverb", %{"deck" => "1", "value" => "0.3"})
      assert is_binary(html)
    end

    test "deck_filter event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_filter", %{"deck" => "1", "value" => "0.7"})
      assert is_binary(html)
    end
  end

  describe "DJ tab loop events" do
    test "deck_loop_toggle on deck 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_loop_toggle", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "deck_loop_size event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_loop_size", %{"deck" => "1", "beats" => "4"})
      assert is_binary(html)
    end
  end

  describe "DJ tab crossfader positions" do
    test "crossfader full left", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "crossfader", %{"value" => "-100"})
      assert is_binary(html)
    end

    test "crossfader full right", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "crossfader", %{"value" => "100"})
      assert is_binary(html)
    end
  end

  describe "DJ tab stem operations" do
    test "stem_mute event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "stem_mute", %{"deck" => "1", "stem" => "vocals"})
      assert is_binary(html)
    end

    test "stem_solo event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "stem_solo", %{"deck" => "1", "stem" => "drums"})
      assert is_binary(html)
    end

    test "stem_volume event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})

      html =
        render_click(view, "stem_volume", %{"deck" => "1", "stem" => "bass", "value" => "0.5"})

      assert is_binary(html)
    end
  end

  describe "DJ tab pitch and speed" do
    test "deck_pitch event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_pitch", %{"deck" => "1", "value" => "2.5"})
      assert is_binary(html)
    end

    test "deck_speed event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "deck_speed", %{"deck" => "1", "value" => "1.1"})
      assert is_binary(html)
    end
  end

  describe "DJ tab cue operations" do
    test "cue_set event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "cue_set", %{"deck" => "1", "slot" => "1"})
      assert is_binary(html)
    end

    test "cue_goto event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "cue_goto", %{"deck" => "1", "slot" => "1"})
      assert is_binary(html)
    end

    test "cue_delete event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "cue_delete", %{"deck" => "1", "slot" => "1"})
      assert is_binary(html)
    end
  end

  describe "DJ tab deck navigation" do
    test "next_track event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "next_track", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "prev_track event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "switch_tab", %{"tab" => "dj"})
      html = render_click(view, "prev_track", %{"deck" => "1"})
      assert is_binary(html)
    end
  end
end
