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
      track = track_fixture(%{title: "Test Track Detail", artist: "Test Artist", user_id: user.id})

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

      html = render(view)
      # Pipeline should show as active (if track was found)
      # The dismiss is handled by the event
      render_click(view, "dismiss_pipeline", %{"track-id" => track_id})
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
      assert SoundForgeWeb.DashboardLive.normalize_spectral(10000, 8000) == 100
    end

    test "upload_error_to_string returns human-readable errors" do
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:too_large) =~ "100 MB"
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:not_accepted) =~ "file type"
      assert SoundForgeWeb.DashboardLive.upload_error_to_string(:too_many_files) =~ "max 5"
    end
  end
end
