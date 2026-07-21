defmodule SoundForgeWeb.DashboardHandleInfoExtraTest do
  @moduledoc """
  Tests for DashboardLive handle_info patterns focused on
  pipeline progress, job progress, and lalalai result events.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Info Extra Track",
        artist: "Test Artist",
        duration: 200
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/info_extra.mp3"
    })

    %{track: track}
  end

  describe "pipeline_progress" do
    test "handles pipeline_progress download stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :download, status: :running, progress: 50}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "handles pipeline_progress processing stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{track_id: track.id, stage: :processing, status: :running, progress: 75}}
      )

      html = render(view)
      assert is_binary(html)
    end

    test "handles pipeline_progress failed stage", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track.id,
           stage: :analysis,
           status: :failed,
           progress: 0,
           error: "Analysis failed"
         }}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "job_progress" do
    test "handles job_progress", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(
        view.pid,
        {:job_progress,
         %{job_id: "fake-job-id", worker: "DownloadWorker", progress: 30, message: "Downloading"}}
      )

      html = render(view)
      assert is_binary(html)
    end
  end

  describe "lalalai events" do
    test "handles lalalai_connection_result valid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:ok, :valid}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles lalalai_connection_result error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_connection_result, {:error, :unauthorized}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles lalalai_modal_test_result valid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_modal_test_result, {:ok, :valid}, "test-key-123"})
      html = render(view)
      assert is_binary(html)
    end

    test "handles lalalai_modal_test_result error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      send(view.pid, {:lalalai_modal_test_result, {:error, :invalid_key}, "bad-key"})
      html = render(view)
      assert is_binary(html)
    end
  end

  describe "DOWN messages" do
    test "handles DOWN message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      ref = make_ref()
      send(view.pid, {:DOWN, ref, :process, self(), :normal})
      html = render(view)
      assert is_binary(html)
    end
  end
end
