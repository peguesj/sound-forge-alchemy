defmodule SoundForgeWeb.DashboardDjEventsTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      title: "DJ Test Track",
      artist: "Test DJ",
      user_id: user.id,
      duration: 300
    })
    %{track: track}
  end

  describe "DJ tab events" do
    test "crossfader event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "crossfader", %{"value" => "50"})
      assert is_binary(html)
    end

    test "set_deck_volume event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_deck_volume", %{"deck" => "1", "level" => "80"})
      assert is_binary(html)
    end

    test "set_pitch event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_pitch", %{"deck" => "1", "value" => "2.5"})
      assert is_binary(html)
    end

    test "pitch_reset event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "pitch_reset", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "set_crossfader_curve event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_crossfader_curve", %{"curve" => "smooth"})
      assert is_binary(html)
    end

    test "toggle_play event without loaded track", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_play", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_in event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_in", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_out event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_out", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_toggle event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_toggle", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "loop_size event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "loop_size", %{"deck" => "1", "beats" => "4"})
      assert is_binary(html)
    end

    test "jog_scratch event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "jog_scratch", %{"deck" => "1", "delta" => "10"})
      assert is_binary(html)
    end

    test "toggle_midi_sync event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_midi_sync", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "master_sync event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "master_sync")
      assert is_binary(html)
    end

    test "set_cue event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_cue", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "toggle_eq_kill event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "toggle_eq_kill", %{"deck" => "1", "band" => "low"})
      assert is_binary(html)
    end

    test "set_filter event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "set_filter", %{"deck" => "1", "mode" => "lowpass", "cutoff" => "0.5"})
      assert is_binary(html)
    end

    test "skip_section event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "skip_section", %{"deck" => "1", "direction" => "forward"})
      assert is_binary(html)
    end

    test "sync_deck event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "sync_deck", %{"deck" => "1"})
      assert is_binary(html)
    end

    test "load_track onto deck 1", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "load_track", %{"deck" => "1", "track_id" => track.id})
      assert is_binary(html)
    end

    test "load_track onto deck 2", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "load_track", %{"deck" => "2", "track_id" => track.id})
      assert is_binary(html)
    end

    test "time_update event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "time_update", %{"deck" => "1", "position" => "120.5"})
      assert is_binary(html)
    end

    test "deck_stopped event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "deck_stopped", %{"deck" => "1"})
      assert is_binary(html)
    end
  end
end
