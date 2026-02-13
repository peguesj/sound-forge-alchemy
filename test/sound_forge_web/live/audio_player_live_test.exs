defmodule SoundForgeWeb.AudioPlayerLiveTest do
  use SoundForgeWeb.ConnCase
  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  defp create_track_with_stems(%{user: user}) do
    track = track_fixture(%{title: "Player Test Track", user_id: user.id})
    pj = processing_job_fixture(%{track_id: track.id})

    vocals = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})
    drums = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums})
    bass = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :bass})
    other = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :other})

    %{track: track, stems: [vocals, drums, bass, other]}
  end

  describe "audio player rendering" do
    setup [:create_track_with_stems]

    test "renders audio player on track detail page", %{conn: conn, track: track} do
      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")

      assert html =~ "audio-player-"
      assert html =~ "Play"
      assert html =~ "Master volume"
    end

    test "renders per-stem controls", %{conn: conn, track: track} do
      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")

      assert html =~ "Vocals"
      assert html =~ "Drums"
      assert html =~ "Bass"
      assert html =~ "Other"
    end

    test "renders solo and mute buttons for each stem", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")

      assert has_element?(view, "button[aria-label='Solo vocals']")
      assert has_element?(view, "button[aria-label='Mute vocals']")
      assert has_element?(view, "button[aria-label='Solo drums']")
      assert has_element?(view, "button[aria-label='Mute drums']")
    end

    test "renders volume sliders for each stem", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")

      assert has_element?(view, "input[aria-label='Vocals volume']")
      assert has_element?(view, "input[aria-label='Drums volume']")
      assert has_element?(view, "input[aria-label='Bass volume']")
      assert has_element?(view, "input[aria-label='Other volume']")
    end
  end

  describe "audio player events" do
    setup [:create_track_with_stems]

    test "toggle_play toggles playing state", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")

      # Initially shows "Play" button
      assert has_element?(view, "button[aria-label='Play']")

      # Click play
      view
      |> element("button[aria-label='Play']")
      |> render_click()

      # Now should show "Pause"
      assert has_element?(view, "button[aria-label='Pause']")

      # Click again to pause
      view
      |> element("button[aria-label='Pause']")
      |> render_click()

      assert has_element?(view, "button[aria-label='Play']")
    end

    test "solo_stem toggles solo state", %{conn: conn, track: track} do
      {:ok, view, html} = live(conn, ~p"/tracks/#{track.id}")

      # Initially no stems are soloed
      assert html =~ ~s(aria-pressed="false")

      # Solo vocals
      view
      |> element("button[aria-label='Solo vocals']")
      |> render_click()

      html = render(view)
      # Vocals solo button should now be pressed
      assert html =~ "bg-yellow-500"
    end

    test "toggle_stem toggles mute state", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/tracks/#{track.id}")

      # Mute drums
      view
      |> element("button[aria-label='Mute drums']")
      |> render_click()

      html = render(view)
      # Drums mute button should show red
      assert html =~ "bg-red-500"
    end
  end

  describe "time formatting" do
    test "displays initial time as 00:00", %{conn: conn, user: user} do
      track = track_fixture(%{title: "Time Track", user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      {:ok, _view, html} = live(conn, ~p"/tracks/#{track.id}")
      assert html =~ "00:00 / 00:00"
    end
  end
end
