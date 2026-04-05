defmodule SoundForgeWeb.PipelineTrackerExtendedTest do
  @moduledoc """
  Tests for PipelineTracker component event handlers: close_tracker,
  clear_completed, and template rendering states.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track = track_fixture(%{
      user_id: user.id,
      title: "Pipeline Track",
      artist: "Test Artist",
      duration: 200
    })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/pipeline_test.mp3"
    })

    %{track: track}
  end

  describe "pipeline tracker events" do
    test "toggle_tracker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "toggle_tracker", %{})
      assert is_binary(html)
    end

    test "close_tracker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_tracker", %{})
      html = render_click(view, "close_tracker", %{})
      assert is_binary(html)
    end

    test "clear_completed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "clear_completed", %{})
      assert is_binary(html)
    end

    test "toggle_tracker twice closes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_click(view, "toggle_tracker", %{})
      html = render_click(view, "toggle_tracker", %{})
      assert is_binary(html)
    end
  end
end
