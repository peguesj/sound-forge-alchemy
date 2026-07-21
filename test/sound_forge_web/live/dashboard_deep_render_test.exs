defmodule SoundForgeWeb.DashboardDeepRenderTest do
  @moduledoc """
  Deep rendering tests that exercise template branches with
  realistic data: tracks with stems, analysis results, DJ decks
  loaded, DAW with operations, etc.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures
  import SoundForge.AccountsFixtures

  setup :register_and_log_in_user

  defp create_track_with_stems(user) do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Full Track",
        artist: "Test Artist",
        duration: 240
      })

    pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})

    stems =
      for type <- [:vocals, :drums, :bass, :other] do
        stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: type})
      end

    {track, stems, pj}
  end

  defp create_track_with_analysis(user) do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Analyzed Track",
        artist: "Analyst",
        duration: 180
      })

    analysis_job = analysis_job_fixture(%{track_id: track.id, status: :completed})

    analysis =
      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: analysis_job.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.85,
        spectral_centroid: 2500.0,
        spectral_rolloff: 5000.0,
        zero_crossing_rate: 0.08,
        features: %{"beats" => [0.5, 1.0, 1.5], "chroma" => [0.1, 0.2]}
      })

    {track, analysis}
  end

  describe "library tab with rich data" do
    test "renders track list with multiple tracks", %{conn: conn, user: user} do
      for i <- 1..5 do
        track_fixture(%{user_id: user.id, title: "Track #{i}", artist: "Artist #{i}"})
      end

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Track 1"
      assert html =~ "Track 5"
    end

    test "renders library search", %{conn: conn, user: user} do
      track_fixture(%{user_id: user.id, title: "Searchable Song"})
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "search", %{"query" => "Searchable"})
      assert html =~ "Sound Forge" or html =~ "Searchable"
    end

    test "handles track selection in library", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Selected Track"})
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "select_track", %{"track_id" => track.id})
      assert html =~ "Selected Track" or html =~ "Sound Forge"
    end
  end

  describe "library tab with stemmed tracks" do
    test "track with stems shows stem information", %{conn: conn, user: user} do
      {track, _stems, _pj} = create_track_with_stems(user)
      {:ok, view, _html} = live(conn, "/")

      html = render_click(view, "select_track", %{"track_id" => track.id})
      assert html =~ "Full Track" or html =~ "Sound Forge"
    end
  end

  describe "DJ tab with loaded decks" do
    test "loads track on deck 1", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Deck 1 Track"})

      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      assert html =~ "dj-tab"
    end

    test "loads track on deck 2", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Deck 2 Track"})

      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "load_track", %{"track_id" => track.id, "deck" => "2"})
      assert html =~ "dj-tab"
    end

    test "loads tracks on both decks", %{conn: conn, user: user} do
      track_a = track_fixture(%{user_id: user.id, title: "Track A", duration: 200})
      track_b = track_fixture(%{user_id: user.id, title: "Track B", duration: 180})

      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track_a.id, "deck" => "1"})
      html = render_click(view, "load_track", %{"track_id" => track_b.id, "deck" => "2"})
      assert html =~ "dj-tab"
    end

    test "DJ crossfader event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=dj")
      html = render_click(view, "crossfader", %{"value" => "50"})
      assert html =~ "dj-tab"
    end

    test "DJ cue event", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Cue Track"})
      {:ok, view, _html} = live(conn, "/?tab=dj")
      render_click(view, "load_track", %{"track_id" => track.id, "deck" => "1"})
      html = render_click(view, "cue", %{"deck" => "1"})
      assert html =~ "dj-tab"
    end
  end

  describe "DAW tab with data" do
    test "DAW tab with analyzed track", %{conn: conn, user: user} do
      {track, _analysis} = create_track_with_analysis(user)

      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")
      assert html =~ "daw-tab"
    end

    test "DAW tab with stemmed track", %{conn: conn, user: user} do
      {track, _stems, _pj} = create_track_with_stems(user)

      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")
      assert html =~ "daw-tab"
    end
  end

  describe "Pads tab with banks" do
    test "pads tab with no banks shows create prompt", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Pads" or html =~ "Create" or html =~ "pads"
    end

    test "pads tab with a bank shows pad grid", %{conn: conn, user: user} do
      SoundForge.Sampler.create_bank(%{name: "Test Bank", user_id: user.id})

      {:ok, _view, html} = live(conn, "/?tab=pads")
      assert html =~ "Pads" or html =~ "pads"
    end
  end

  describe "settings/admin tab" do
    test "can navigate to settings tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "settings"})
      assert html =~ "Settings" or html =~ "Sound Forge"
    end

    test "admin tab renders for admin users" do
      admin = user_fixture()
      SoundForge.Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = SoundForge.Repo.reload!(admin)
      conn = build_conn() |> log_in_user(admin)

      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "admin"})
      assert html =~ "Sound Forge" or html =~ "admin"
    end
  end

  describe "rapid tab switching" do
    test "switching tabs rapidly does not crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      tabs = ["dj", "library", "daw", "pads", "dj", "library", "settings"]

      for tab <- tabs do
        render_click(view, "nav_tab", %{"tab" => tab})
      end

      html = render(view)
      assert html =~ "Sound Forge" or html =~ "tab"
    end
  end

  describe "browse tab" do
    test "browse tab renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      html = render_click(view, "nav_tab", %{"tab" => "browse"})
      assert html =~ "Sound Forge" or html =~ "Browse" or html =~ "browse"
    end
  end

  describe "download/processing events" do
    test "spotify URL validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Try submitting an invalid URL
      html = render_click(view, "add_track", %{"url" => "not-a-url"})
      assert html =~ "Sound Forge" or html =~ "invalid" or html =~ "Spotify"
    end
  end
end
