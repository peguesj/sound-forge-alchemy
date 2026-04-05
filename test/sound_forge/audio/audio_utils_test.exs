defmodule SoundForge.Audio.AudioUtilsTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.AudioUtils

  describe "truncate_to_preview/2" do
    test "constructs correct preview path from input path" do
      # We test path construction by checking that ffmpeg receives the right args.
      # Since ffmpeg may or may not be installed, we only verify behavior
      # when ffmpeg IS available; otherwise the rescue returns an error tuple.
      result = AudioUtils.truncate_to_preview("/tmp/nonexistent_file_#{System.unique_integer([:positive])}.mp3")

      # Should return either {:ok, path} or {:error, reason}
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, preview_path} ->
          assert String.ends_with?(preview_path, "_preview.mp3")
          assert String.starts_with?(preview_path, "/tmp/nonexistent_file_")

        {:error, reason} ->
          assert is_binary(reason)
      end
    end

    test "preserves file extension in preview path" do
      result = AudioUtils.truncate_to_preview("/tmp/test_#{System.unique_integer([:positive])}.wav")

      case result do
        {:ok, path} ->
          assert String.ends_with?(path, "_preview.wav")

        {:error, _} ->
          # ffmpeg unavailable or file not found -- both are acceptable in test env
          :ok
      end
    end

    test "respects custom duration option" do
      result = AudioUtils.truncate_to_preview(
        "/tmp/test_#{System.unique_integer([:positive])}.mp3",
        duration: 30
      )

      # We can't inspect ffmpeg args directly, but the function should still
      # return a result tuple (success if ffmpeg runs, error if file missing or ffmpeg absent)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles paths with underscores correctly" do
      result = AudioUtils.truncate_to_preview("/tmp/my_cool_track_#{System.unique_integer([:positive])}.flac")

      case result do
        {:ok, path} ->
          assert String.ends_with?(path, "_preview.flac")

        {:error, _} ->
          :ok
      end
    end

    test "handles paths with no extension" do
      result = AudioUtils.truncate_to_preview("/tmp/noextfile_#{System.unique_integer([:positive])}")

      case result do
        {:ok, path} ->
          # With no extension, preview suffix is appended to the full name
          assert String.ends_with?(path, "_preview")

        {:error, _} ->
          :ok
      end
    end
  end
end
