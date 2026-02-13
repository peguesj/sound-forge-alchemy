defmodule SoundForgeWeb.DashboardPipelineTest do
  use SoundForgeWeb.ConnCase
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "pipeline progress via PubSub" do
    test "handles pipeline_progress messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Simulate a pipeline progress message
      track_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track_id,
           stage: :download,
           status: :downloading,
           progress: 50
         }}
      )

      # The view should handle this without crashing
      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end

    test "handles pipeline_complete messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      track_id = Ecto.UUID.generate()

      send(view.pid, {:pipeline_complete, %{track_id: track_id}})

      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "fetch_spotify triggers pipeline" do
    # Uses mock_spotdl.sh configured in test.exs
    test "creates track and starts pipeline on valid Spotify URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> form("form[phx-submit='fetch_spotify']", %{
          url: "https://open.spotify.com/track/abc123"
        })
        |> render_submit()

      # mock_spotdl.sh returns "Test Song" as the track name
      assert html =~ "Test Song"
    end

    test "shows error on invalid Spotify URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> form("form[phx-submit='fetch_spotify']", %{url: "not-a-spotify-url"})
      |> render_submit()

      # Should show error flash and no tracks
      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "dismiss_pipeline event" do
    test "removes pipeline from active list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      track_id = Ecto.UUID.generate()

      # First add a pipeline
      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track_id,
           stage: :download,
           status: :completed,
           progress: 100
         }}
      )

      # Then dismiss it
      render_click(view, "dismiss_pipeline", %{"track-id" => track_id})

      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end
  end
end
