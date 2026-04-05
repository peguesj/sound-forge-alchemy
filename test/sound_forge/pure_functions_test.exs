defmodule SoundForge.PureFunctionsTest do
  @moduledoc """
  Tests for pure helper functions across various modules.
  These are functions with no side effects that can be tested in isolation.
  """
  use ExUnit.Case, async: true

  describe "MIDI.ActionExecutor.cc_to_float/1" do
    test "converts 0 to 0.0" do
      assert SoundForge.MIDI.ActionExecutor.cc_to_float(0) == 0.0
    end

    test "converts 64 to midpoint" do
      result = SoundForge.MIDI.ActionExecutor.cc_to_float(64)
      assert_in_delta result, 0.504, 0.01
    end

    test "converts 127 to 1.0" do
      assert SoundForge.MIDI.ActionExecutor.cc_to_float(127) == 1.0
    end

    test "clamps values above 127" do
      assert SoundForge.MIDI.ActionExecutor.cc_to_float(200) == 1.0
    end

    test "returns 0.0 for non-integer" do
      assert SoundForge.MIDI.ActionExecutor.cc_to_float("abc") == 0.0
    end

    test "returns 0.0 for nil" do
      assert SoundForge.MIDI.ActionExecutor.cc_to_float(nil) == 0.0
    end
  end

  describe "Music.Spotify module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForge.Music.Spotify)
    end

    test "exports fetch_metadata/1" do
      assert {:fetch_metadata, 1} in SoundForge.Music.Spotify.__info__(:functions)
    end
  end

  describe "Spotify.URLParser" do
    test "parses track URL" do
      result = SoundForge.Spotify.URLParser.parse("https://open.spotify.com/track/abc123")
      assert {:ok, %{id: "abc123", type: "track"}} = result
    end

    test "parses album URL" do
      result = SoundForge.Spotify.URLParser.parse("https://open.spotify.com/album/xyz456")
      assert {:ok, %{id: "xyz456", type: "album"}} = result
    end

    test "parses playlist URL" do
      result = SoundForge.Spotify.URLParser.parse("https://open.spotify.com/playlist/pl789")
      assert {:ok, %{id: "pl789", type: "playlist"}} = result
    end

    test "returns error for invalid URL" do
      result = SoundForge.Spotify.URLParser.parse("not-a-url")
      assert result == :error or match?({:error, _}, result)
    end
  end

  describe "DAW.EditOperation" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForge.DAW.EditOperation)
    end
  end

  describe "DJ structs" do
    test "DeckSession module loaded" do
      assert Code.ensure_loaded?(SoundForge.DJ.DeckSession)
    end

    test "CuePoint module loaded" do
      assert Code.ensure_loaded?(SoundForge.DJ.CuePoint)
    end

    test "StemLoop module loaded" do
      assert Code.ensure_loaded?(SoundForge.DJ.StemLoop)
    end

    test "Timecode module loaded" do
      assert Code.ensure_loaded?(SoundForge.DJ.Timecode)
    end

    test "Chef.Recipe module loaded" do
      assert Code.ensure_loaded?(SoundForge.DJ.Chef.Recipe)
    end
  end

  describe "ErrorHTML" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.ErrorHTML)
    end
  end

  describe "ImpersonateController module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(SoundForgeWeb.ImpersonateController)
    end
  end

  describe "Mix.Tasks modules" do
    test "BackfillAlbums is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.BackfillAlbums)
    end

    test "FixDownloadPaths is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.FixDownloadPaths)
    end

    test "Sfa.Touchosc.Generate is loaded" do
      assert Code.ensure_loaded?(Mix.Tasks.Sfa.Touchosc.Generate)
    end
  end
end
