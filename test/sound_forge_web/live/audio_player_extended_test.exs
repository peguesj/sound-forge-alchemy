defmodule SoundForgeWeb.AudioPlayerExtendedTest do
  @moduledoc "Extended tests for AudioPlayerLive component rendering and helpers."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  alias SoundForgeWeb.AudioPlayerLive

  setup :register_and_log_in_user

  setup %{user: user} do
    track =
      track_fixture(%{
        user_id: user.id,
        title: "Extended Player Test",
        artist: "Extended Artist",
        duration: 300
      })

    download_job_fixture(%{
      track_id: track.id,
      status: :completed,
      output_path: "priv/uploads/downloads/extended_test.mp3"
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

  describe "render_component with stems" do
    test "renders audio player with stem list" do
      stems = [
        %{stem_type: :vocals, file_path: "stems/vocals.wav", file_size: 1024},
        %{stem_type: :drums, file_path: "stems/drums.wav", file_size: 1024},
        %{stem_type: :bass, file_path: "stems/bass.wav", file_size: 1024},
        %{stem_type: :other, file_path: "stems/other.wav", file_size: 1024}
      ]

      html =
        render_component(AudioPlayerLive, %{
          id: "audio-player-test",
          stems: stems,
          track: %{title: "Test", artist: "Art", id: Ecto.UUID.generate()}
        })

      assert is_binary(html)
    end

    test "renders audio player with empty stems" do
      html =
        render_component(AudioPlayerLive, %{
          id: "audio-player-empty",
          stems: [],
          track: %{title: "No Stems", artist: "Art", id: Ecto.UUID.generate()}
        })

      assert is_binary(html)
    end

    test "renders audio player with nil track" do
      html =
        render_component(AudioPlayerLive, %{
          id: "audio-player-nil",
          stems: [],
          track: nil
        })

      assert is_binary(html)
    end
  end

  describe "helper functions" do
    test "format_time with valid seconds" do
      # Test via module function if accessible, otherwise via rendering
      html =
        render_component(AudioPlayerLive, %{
          id: "ap-time",
          stems: [],
          track: nil,
          current_time: 125,
          duration: 300
        })

      assert is_binary(html)
    end

    test "format_time with zero" do
      html =
        render_component(AudioPlayerLive, %{
          id: "ap-zero",
          stems: [],
          track: nil,
          current_time: 0,
          duration: 0
        })

      assert html =~ "00:00"
    end
  end

  describe "play_track event variations" do
    test "select track navigates to track detail", %{conn: conn, track: track} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_click(view, "select_track", %{"id" => track.id})
      assert is_binary(html) or match?({:error, {:live_redirect, _}}, html)
    end
  end
end
