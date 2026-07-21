defmodule SoundForge.StorageTest do
  use ExUnit.Case, async: false

  alias SoundForge.Storage

  setup %{test: test_name} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "sound_forge_storage_test_#{:erlang.phash2(test_name)}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    Application.put_env(:sound_forge, :storage_path, tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      Application.delete_env(:sound_forge, :storage_path)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "ensure_directories!/0" do
    test "creates all required directories" do
      Storage.ensure_directories!()
      assert File.dir?(Storage.downloads_path())
      assert File.dir?(Storage.stems_path())
      assert File.dir?(Storage.analysis_path())
    end
  end

  describe "store_file/3" do
    test "copies file to storage", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "source.txt")
      File.write!(source, "test content")

      assert {:ok, dest_path} = Storage.store_file(source, "test", "stored.txt")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "test content"
    end
  end

  describe "file_exists?/2" do
    test "returns true for existing files", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "check")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "exists.txt"), "content")

      assert Storage.file_exists?("check", "exists.txt")
    end

    test "returns false for missing files" do
      refute Storage.file_exists?("check", "nope.txt")
    end
  end

  describe "delete_file/2" do
    test "removes existing file", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "delete")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "doomed.txt"), "bye")

      assert :ok = Storage.delete_file("delete", "doomed.txt")
      refute File.exists?(Path.join(dir, "doomed.txt"))
    end

    test "returns ok for missing files" do
      assert :ok = Storage.delete_file("delete", "ghost.txt")
    end
  end

  describe "stats/0" do
    test "returns storage statistics", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "stats"))
      File.write!(Path.join(tmp_dir, "stats/file1.txt"), "hello")

      stats = Storage.stats()
      assert stats.file_count >= 1
      assert stats.total_size_bytes > 0
    end

    test "returns zeros for empty storage" do
      stats = Storage.stats()
      assert stats.file_count == 0
    end
  end

  describe "validate_audio_file/1" do
    test "returns :ok for valid MP3 file", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      valid_mp3 = Path.join(audio_dir, "sample.mp3")
      File.write!(valid_mp3, <<0xFF, 0xFB>> <> String.duplicate("x", 2048))

      assert :ok = Storage.validate_audio_file(valid_mp3)
    end

    test "returns error for non-existent file" do
      assert {:error, msg} = Storage.validate_audio_file("/nonexistent/file.mp3")
      assert msg =~ "does not exist"
    end

    test "returns error for file that's too small", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      tiny_file = Path.join(audio_dir, "tiny.mp3")
      File.write!(tiny_file, "x")

      assert {:error, msg} = Storage.validate_audio_file(tiny_file)
      assert msg =~ "too small"
    end

    test "returns error for file with invalid audio header", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      invalid_file = Path.join(audio_dir, "invalid.mp3")
      File.write!(invalid_file, String.duplicate("x", 2048))

      assert {:error, msg} = Storage.validate_audio_file(invalid_file)
      assert msg =~ "does not appear to be a valid audio file"
    end

    test "validates FLAC header", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      flac_file = Path.join(audio_dir, "sample.flac")
      File.write!(flac_file, "fLaC" <> String.duplicate("x", 2048))

      assert :ok = Storage.validate_audio_file(flac_file)
    end

    test "validates OggS header", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      ogg_file = Path.join(audio_dir, "sample.ogg")
      File.write!(ogg_file, "OggS" <> String.duplicate("x", 2048))

      assert :ok = Storage.validate_audio_file(ogg_file)
    end

    test "validates ID3 (MP3) header", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      mp3_file = Path.join(audio_dir, "id3.mp3")
      File.write!(mp3_file, "ID3" <> String.duplicate("x", 2048))

      assert :ok = Storage.validate_audio_file(mp3_file)
    end
  end

  describe "validate_download_path/1" do
    test "returns {:ok, path} for valid file", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      valid_mp3 = Path.join(audio_dir, "sample.mp3")
      File.write!(valid_mp3, <<0xFF, 0xFB>> <> String.duplicate("x", 2048))

      assert {:ok, resolved} = Storage.validate_download_path(valid_mp3)
      assert String.ends_with?(resolved, "sample.mp3")
    end

    test "returns error for invalid file" do
      assert {:error, _} = Storage.validate_download_path("/nonexistent.mp3")
    end

    test "returns error for file with bad audio header", %{tmp_dir: tmp_dir} do
      audio_dir = Path.join(tmp_dir, "audio")
      File.mkdir_p!(audio_dir)
      bad_file = Path.join(audio_dir, "bad.mp3")
      File.write!(bad_file, String.duplicate("x", 2048))

      assert {:error, _} = Storage.validate_download_path(bad_file)
    end
  end
end
