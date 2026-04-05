defmodule SoundForge.StorageExtendedTest do
  use ExUnit.Case, async: true

  alias SoundForge.Storage

  describe "path helpers" do
    test "base_path returns configured or default" do
      path = Storage.base_path()
      assert is_binary(path)
    end

    test "downloads_path includes downloads" do
      assert Storage.downloads_path() =~ "downloads"
    end

    test "stems_path includes stems" do
      assert Storage.stems_path() =~ "stems"
    end

    test "analysis_path includes analysis" do
      assert Storage.analysis_path() =~ "analysis"
    end
  end

  describe "file_path/2" do
    test "joins subdirectory and filename" do
      path = Storage.file_path("downloads", "test.mp3")
      assert path =~ "downloads"
      assert path =~ "test.mp3"
    end
  end

  describe "resolve_path/1" do
    test "absolute path returned as-is" do
      assert Storage.resolve_path("/absolute/path") == "/absolute/path"
    end

    test "priv/ relative path resolved to cwd" do
      path = Storage.resolve_path("priv/uploads/test.mp3")
      assert String.starts_with?(path, "/")
      assert path =~ "priv/uploads/test.mp3"
    end

    test "other paths returned as-is" do
      assert Storage.resolve_path("something.mp3") == "something.mp3"
    end
  end

  describe "validate_audio_file/1" do
    test "returns error for nonexistent file" do
      assert {:error, msg} = Storage.validate_audio_file("/nonexistent/file.mp3")
      assert msg =~ "does not exist"
    end

    test "returns error for too-small file" do
      path = Path.join(System.tmp_dir!(), "tiny_audio_test.mp3")
      File.write!(path, "x")
      assert {:error, msg} = Storage.validate_audio_file(path)
      assert msg =~ "too small" || msg =~ "corrupt"
      File.rm(path)
    end

    test "returns error for non-audio file" do
      path = Path.join(System.tmp_dir!(), "not_audio_test.txt")
      File.write!(path, String.duplicate("NOT AUDIO DATA", 200))
      assert {:error, msg} = Storage.validate_audio_file(path)
      assert msg =~ "not" || msg =~ "unrecognized"
      File.rm(path)
    end

    test "validates MP3 with ID3 header" do
      path = Path.join(System.tmp_dir!(), "valid_audio_test.mp3")
      File.write!(path, "ID3" <> String.duplicate(<<0>>, 2000))
      assert :ok = Storage.validate_audio_file(path)
      File.rm(path)
    end

    test "validates WAV with RIFF header" do
      path = Path.join(System.tmp_dir!(), "valid_audio_test.wav")
      File.write!(path, "RIFF" <> String.duplicate(<<0>>, 2000))
      assert :ok = Storage.validate_audio_file(path)
      File.rm(path)
    end

    test "validates FLAC header" do
      path = Path.join(System.tmp_dir!(), "valid_audio_test.flac")
      File.write!(path, "fLaC" <> String.duplicate(<<0>>, 2000))
      assert :ok = Storage.validate_audio_file(path)
      File.rm(path)
    end

    test "validates Ogg header" do
      path = Path.join(System.tmp_dir!(), "valid_audio_test.ogg")
      File.write!(path, "OggS" <> String.duplicate(<<0>>, 2000))
      assert :ok = Storage.validate_audio_file(path)
      File.rm(path)
    end
  end

  describe "validate_download_path/1" do
    test "returns error for missing file" do
      assert {:error, _} = Storage.validate_download_path("/no/such/file.mp3")
    end

    test "returns ok with resolved path for valid audio" do
      path = Path.join(System.tmp_dir!(), "dl_valid_test.mp3")
      File.write!(path, "ID3" <> String.duplicate(<<0>>, 2000))
      assert {:ok, resolved} = Storage.validate_download_path(path)
      assert resolved == path
      File.rm(path)
    end
  end

  describe "store_file/3" do
    test "copies file to destination" do
      src = Path.join(System.tmp_dir!(), "store_src_test.mp3")
      File.write!(src, "test data")

      dest_dir = Path.join(System.tmp_dir!(), "sfa_store_test_#{:rand.uniform(100_000)}")

      assert {:ok, dest_path} = Storage.store_file(src, dest_dir, "stored.mp3")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "test data"

      File.rm(src)
      File.rm_rf(dest_dir)
    end
  end

  describe "stats/0" do
    test "returns stats map" do
      stats = Storage.stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :base_path)
      assert Map.has_key?(stats, :file_count)
      assert Map.has_key?(stats, :total_size_bytes)
      assert Map.has_key?(stats, :total_size_mb)
    end
  end

  describe "file_exists?/2" do
    test "returns false for nonexistent file" do
      refute Storage.file_exists?("nonexistent_dir", "nonexistent_file.mp3")
    end
  end

  describe "delete_file/2" do
    test "returns ok for nonexistent file (idempotent)" do
      assert :ok = Storage.delete_file("nonexistent_dir", "nonexistent_file.mp3")
    end
  end
end
