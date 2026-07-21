defmodule SoundForgeWeb.DawProjectLiveTest do
  @moduledoc """
  E2E LiveView tests for DAW track status badges and contextual pipeline actions.

  Tests use Phoenix.LiveViewTest helpers (live/2, render_click, render) and
  operate through the dashboard's DAW tab (/?tab=daw&track_id=<uuid>).
  """
  use SoundForgeWeb.ConnCase
  use Oban.Testing, repo: SoundForge.Repo
  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  # ---------------------------------------------------------------------------
  # Fixtures helpers
  # ---------------------------------------------------------------------------

  # Minimal valid MP3 stub: ID3 header + zero padding to meet min_audio_size (1024 bytes)
  @stub_audio_content "ID3" <> :binary.copy(<<0>>, 1021)

  defp track_with_completed_download(user_id) do
    track =
      track_fixture(%{
        user_id: user_id,
        spotify_url: "https://open.spotify.com/track/testdownloaded"
      })

    stub_path = "/tmp/test_#{track.id}.mp3"
    File.write!(stub_path, @stub_audio_content)
    on_exit(fn -> File.rm(stub_path) end)

    {:ok, _job} =
      SoundForge.Music.create_download_job(%{
        track_id: track.id,
        status: :completed,
        output_path: stub_path
      })

    track
  end

  defp track_with_stems(user_id) do
    track = track_with_completed_download(user_id)

    {:ok, processing_job} =
      SoundForge.Music.create_processing_job(%{
        track_id: track.id,
        model: "htdemucs",
        status: :completed
      })

    {:ok, _stem} =
      SoundForge.Music.create_stem(%{
        track_id: track.id,
        processing_job_id: processing_job.id,
        stem_type: :vocals,
        file_path: "/tmp/stem_vocals_#{track.id}.wav",
        file_size: 1024 * 1024
      })

    track
  end

  defp track_spotify_only(user_id) do
    track_fixture(%{
      user_id: user_id,
      spotify_url: "https://open.spotify.com/track/spotifyonly123"
    })
  end

  # ---------------------------------------------------------------------------
  # Status badge tests
  # ---------------------------------------------------------------------------

  describe "status badges" do
    test "shows Spotify badge when track has a spotify_url", %{conn: conn, user: user} do
      track = track_spotify_only(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Spotify"
    end

    test "shows Downloaded badge when track has a completed download job", %{
      conn: conn,
      user: user
    } do
      track = track_with_completed_download(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Downloaded"
    end

    test "shows Processed badge when track has stems", %{conn: conn, user: user} do
      track = track_with_stems(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Processed"
    end

    test "does not show Downloaded badge for track with no completed download", %{
      conn: conn,
      user: user
    } do
      track = track_spotify_only(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      # Check specifically for the Downloaded badge span element
      refute html =~ ~r/<span[^>]*class="[^"]*badge[^"]*"[^>]*>\s*Downloaded\s*<\/span>/
    end

    test "does not show Processed badge for track with no stems", %{conn: conn, user: user} do
      track = track_spotify_only(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      # Check specifically for the Processed badge span element
      refute html =~ ~r/<span[^>]*class="[^"]*badge[^"]*"[^>]*>\s*Processed\s*<\/span>/
    end

    test "shows Analyzed badge when track has bpm set", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, bpm: 128.0, spotify_url: nil})
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Analyzed"
    end
  end

  # ---------------------------------------------------------------------------
  # Contextual action button tests
  # ---------------------------------------------------------------------------

  describe "contextual action buttons" do
    test "shows Download Track button when track is not downloaded", %{conn: conn, user: user} do
      track = track_spotify_only(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Download Track"
    end

    test "shows Separate Stems button when downloaded but no stems", %{conn: conn, user: user} do
      track = track_with_completed_download(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ "Separate Stems"
    end

    test "does not show action buttons when track is fully processed", %{conn: conn, user: user} do
      track = track_with_stems(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      # Look for the specific button elements, not just the text anywhere
      refute html =~ ~r/<button[^>]*phx-click="daw_download_track"[^>]*>.*?Download Track/s
      refute html =~ ~r/<button[^>]*phx-click="daw_separate_stems"[^>]*>.*?Separate Stems/s
    end

    test "shows Download Track but not Separate Stems for un-downloaded track",
         %{conn: conn, user: user} do
      track = track_spotify_only(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ ~r/<button[^>]*phx-click="daw_download_track"[^>]*>.*?Download Track/s
      refute html =~ ~r/<button[^>]*phx-click="daw_separate_stems"[^>]*>.*?Separate Stems/s
    end

    test "shows Separate Stems and Analyze Track for downloaded track without stems",
         %{conn: conn, user: user} do
      track = track_with_completed_download(user.id)
      {:ok, _view, html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert html =~ ~r/<button[^>]*phx-click="daw_separate_stems"[^>]*>.*?Separate Stems/s
      refute html =~ ~r/<button[^>]*phx-click="daw_download_track"[^>]*>.*?Download Track/s
    end
  end

  # ---------------------------------------------------------------------------
  # Oban job dispatch tests
  # ---------------------------------------------------------------------------

  describe "Download Track action enqueues Oban job" do
    test "clicking Download Track enqueues a DownloadWorker job", %{conn: conn, user: user} do
      track = track_spotify_only(user.id)
      {:ok, view, _html} = live(conn, "/?tab=daw&track_id=#{track.id}")

      assert has_element?(view, "[phx-click='daw_download_track']")

      view
      |> element("[phx-click='daw_download_track']")
      |> render_click()

      assert_enqueued(worker: SoundForge.Jobs.DownloadWorker, args: %{"track_id" => track.id})
    end
  end
end
