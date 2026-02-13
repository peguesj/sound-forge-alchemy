defmodule SoundForge.StorageTest do
  use ExUnit.Case, async: true

  alias SoundForge.Storage

  @tmp_dir System.tmp_dir!() |> Path.join("sound_forge_storage_test")

  setup do
    File.rm_rf!(@tmp_dir)
    File.mkdir_p!(@tmp_dir)

    Application.put_env(:sound_forge, :storage_path, @tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
      Application.delete_env(:sound_forge, :storage_path)
    end)

    :ok
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
    test "copies file to storage" do
      source = Path.join(@tmp_dir, "source.txt")
      File.write!(source, "test content")

      assert {:ok, dest_path} = Storage.store_file(source, "test", "stored.txt")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "test content"
    end
  end

  describe "file_exists?/2" do
    test "returns true for existing files" do
      dir = Path.join(@tmp_dir, "check")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "exists.txt"), "content")

      assert Storage.file_exists?("check", "exists.txt")
    end

    test "returns false for missing files" do
      refute Storage.file_exists?("check", "nope.txt")
    end
  end

  describe "delete_file/2" do
    test "removes existing file" do
      dir = Path.join(@tmp_dir, "delete")
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
    test "returns storage statistics" do
      File.mkdir_p!(Path.join(@tmp_dir, "stats"))
      File.write!(Path.join(@tmp_dir, "stats/file1.txt"), "hello")

      stats = Storage.stats()
      assert stats.file_count >= 1
      assert stats.total_size_bytes > 0
    end

    test "returns zeros for empty storage" do
      stats = Storage.stats()
      assert stats.file_count == 0
    end
  end
end
