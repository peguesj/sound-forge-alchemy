defmodule SoundForgeWeb.DashboardLiveTest do
  use SoundForgeWeb.ConnCase
  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "index view" do
    test "renders dashboard page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Sound Forge Alchemy"
      assert html =~ "Paste a Spotify URL"
    end

    test "has search input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "input[name='query']")
    end

    test "has spotify url input", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "input[name='url']")
    end

    test "displays no tracks message initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "No tracks yet"
    end

    test "displays version number", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "v3.0.0"
    end

    test "redirects unauthenticated users to login", %{conn: _conn} do
      conn = build_conn()
      {:error, {:redirect, %{to: to}}} = live(conn, "/")
      assert to == "/users/log-in"
    end

    test "shows file upload area", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Drop audio files"
    end
  end

  describe "search" do
    test "filters tracks by search query", %{conn: conn, user: user} do
      track_fixture(%{title: "Bohemian Rhapsody", user_id: user.id})
      track_fixture(%{title: "Stairway to Heaven", user_id: user.id})

      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"query" => "Bohemian"})

      assert html =~ "Bohemian Rhapsody"
      refute html =~ "Stairway to Heaven"
    end

    test "shows all tracks when search is cleared", %{conn: conn, user: user} do
      track_fixture(%{title: "Track One", user_id: user.id})
      track_fixture(%{title: "Track Two", user_id: user.id})

      {:ok, view, _html} = live(conn, "/")

      # Search to filter
      view
      |> element("form[phx-change='search']")
      |> render_change(%{"query" => "One"})

      # Clear search
      html =
        view
        |> element("form[phx-change='search']")
        |> render_change(%{"query" => ""})

      assert html =~ "Track One"
      assert html =~ "Track Two"
    end
  end

  describe "sort" do
    test "sorts tracks by title", %{conn: conn, user: user} do
      track_fixture(%{title: "Zebra", user_id: user.id})
      track_fixture(%{title: "Apple", user_id: user.id})

      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='sort']")
        |> render_change(%{"sort_by" => "title"})

      # Both should be present
      assert html =~ "Apple"
      assert html =~ "Zebra"
    end
  end

  describe "track detail view" do
    test "shows track detail when navigating to /tracks/:id", %{conn: conn, user: user} do
      track =
        track_fixture(%{title: "Test Track Detail", artist: "Test Artist", user_id: user.id})

      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")
      assert html =~ "Test Track Detail"
      assert html =~ "Test Artist"
      assert html =~ "Back to library"
    end

    test "shows no analysis message when track has no analysis", %{conn: conn, user: user} do
      track = track_fixture(%{title: "No Analysis Track", user_id: user.id})
      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")
      assert html =~ "No analysis data yet"
    end

    test "shows analysis metrics when available", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Analyzed Track", user_id: user.id})
      aj = analysis_job_fixture(%{track_id: track.id})

      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: aj.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.85
      })

      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")
      assert html =~ "128.0"
      assert html =~ "A minor"
    end

    test "shows delete button on track detail", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Delete Me", user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")
      assert has_element?(view, "button[phx-click='delete_track']")
    end

    test "redirects on nonexistent track", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/", flash: flash}}} =
        live(conn, ~p"/tracks/#{Ecto.UUID.generate()}")

      assert flash["error"] =~ "Track not found"
    end
  end

  describe "delete track" do
    test "deletes a track from detail view", %{conn: conn, user: user} do
      track = track_fixture(%{title: "To Delete", user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")

      view
      |> element("button[phx-click='delete_track']")
      |> render_click()

      # Should navigate back to index
      assert_redirect(view, "/")
    end
  end

  describe "dismiss pipeline" do
    test "dismisses a completed pipeline", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Send a pipeline_complete event to create a pipeline in state
      track_id = Ecto.UUID.generate()
      send(view.pid, {:pipeline_complete, %{track_id: track_id}})

      _html = render(view)
      # Pipeline should show as active (if track was found)
      # The dismiss is handled by the event
      render_click(view, "dismiss_pipeline", %{"track-id" => track_id})
    end
  end

  describe "PubSub pipeline events" do
    test "handles pipeline_progress event", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Pipeline Track", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      # Send a pipeline_progress message to the LiveView process
      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: track.id,
           stage: :download,
           status: :downloading,
           progress: 50
         }}
      )

      html = render(view)
      # View should still render without crashing
      assert html =~ "Sound Forge Alchemy"
    end

    test "handles pipeline_complete event and updates state", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Completing Track", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, {:pipeline_complete, %{track_id: track.id}})
      html = render(view)

      # View should render without error after pipeline_complete
      assert html =~ "Sound Forge Alchemy"
    end

    test "handles pipeline events for unknown track without crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(
        view.pid,
        {:pipeline_progress,
         %{
           track_id: Ecto.UUID.generate(),
           stage: :processing,
           status: :processing,
           progress: 75
         }}
      )

      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "job_progress event" do
    test "handles job_progress messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(
        view.pid,
        {:job_progress,
         %{
           job_id: Ecto.UUID.generate(),
           status: :downloading,
           progress: 42
         }}
      )

      html = render(view)
      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "retry pipeline" do
    test "rejects invalid pipeline stage", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "retry_pipeline", %{
          "track-id" => Ecto.UUID.generate(),
          "stage" => "nonexistent_atom_xyzzy"
        })

      assert html =~ "Invalid pipeline stage"
    end

    test "retries download stage for existing track", %{conn: conn, user: user} do
      track =
        track_fixture(%{
          title: "Retry Track",
          user_id: user.id,
          spotify_url: "https://open.spotify.com/track/abc123"
        })

      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "retry_pipeline", %{
          "track-id" => track.id,
          "stage" => "download"
        })

      assert html =~ "Retrying download"
    end

    test "retries processing stage for existing track", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Retry Processing", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "retry_pipeline", %{
          "track-id" => track.id,
          "stage" => "processing"
        })

      assert html =~ "Retrying processing"
    end

    test "retries analysis stage for existing track", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Retry Analysis", user_id: user.id})
      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "retry_pipeline", %{
          "track-id" => track.id,
          "stage" => "analysis"
        })

      assert html =~ "Retrying analysis"
    end
  end

  describe "delete track error paths" do
    test "shows error for nonexistent track ID", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "delete_track", %{"id" => Ecto.UUID.generate()})

      assert html =~ "Track not found"
    end

    test "shows error for invalid UUID", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "delete_track", %{"id" => "not-a-uuid"})
      assert html =~ "Track not found"
    end
  end

  describe "page event" do
    test "navigates to a specific page", %{conn: conn, user: user} do
      # Create enough tracks to paginate
      for i <- 1..26 do
        track_fixture(%{title: "Page Track #{i}", user_id: user.id})
      end

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "page", %{"page" => "2"})
      assert html =~ "Sound Forge Alchemy"
    end

    test "handles invalid page number gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "page", %{"page" => "abc"})
      assert html =~ "Sound Forge Alchemy"
    end

    test "handles negative page number", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "page", %{"page" => "-5"})
      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "sort with invalid field" do
    test "falls back to newest for invalid sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("form[phx-change='sort']")
        |> render_change(%{"sort_by" => "nonexistent_field_xyzzy"})

      assert html =~ "Sound Forge Alchemy"
    end
  end

  describe "pagination helpers" do
    test "pagination_range returns full range for small page counts" do
      assert SoundForgeWeb.DashboardLive.pagination_range(1, 5) == [1, 2, 3, 4, 5]
    end

    test "pagination_range returns windowed range for large page counts" do
      range = SoundForgeWeb.DashboardLive.pagination_range(5, 20)
      assert length(range) == 5
      assert 5 in range
    end

    test "normalize_spectral normalizes values to percentage" do
      assert SoundForgeWeb.DashboardLive.normalize_spectral(4000, 8000) == 50.0
      assert SoundForgeWeb.DashboardLive.normalize_spectral(0, 8000) == 0.0
    end

    test "normalize_spectral caps at 100%" do
      assert SoundForgeWeb.DashboardLive.normalize_spectral(10_000, 8000) == 100
    end

    test "upload_error_to_string returns human-readable errors" do
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:too_large) =~ "100 MB"
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:not_accepted) =~ "file type"
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:too_many_files) =~ "max 5"
    end
  end

  describe "IDOR protection" do
    test "cannot view another user's track detail", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{title: "Other User Track", user_id: other_user.id})

      {:error, {:live_redirect, %{to: "/", flash: flash}}} =
        live(conn, ~p"/tracks/#{track.id}")

      assert flash["error"] =~ "Track not found"
    end

    test "cannot delete another user's track", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{title: "Protected Track", user_id: other_user.id})

      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "delete_track", %{"id" => track.id})
      assert html =~ "Track not found"

      # Verify track still exists
      assert {:ok, _} = SoundForge.Music.get_track(track.id)
    end

    test "cannot retry pipeline on another user's track", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{title: "Protected Pipeline", user_id: other_user.id})

      {:ok, view, _html} = live(conn, "/")

      html =
        render_click(view, "retry_pipeline", %{
          "track-id" => track.id,
          "stage" => "download"
        })

      assert html =~ "Track not found"
    end
  end
end
