defmodule SoundForge.StorageCleanupTest do
  use SoundForge.DataCase

  alias SoundForge.Storage

  @tmp_dir System.tmp_dir!() |> Path.join("sound_forge_cleanup_test")

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

  describe "cleanup_orphaned/0" do
    test "returns zero when no orphaned files exist" do
      Storage.ensure_directories!()
      assert {:ok, 0} = Storage.cleanup_orphaned()
    end

    test "removes files not referenced in database" do
      Storage.ensure_directories!()
      orphan_path = Path.join(Storage.downloads_path(), "orphan_test.mp3")
      File.write!(orphan_path, "fake audio data")
      assert File.exists?(orphan_path)

      {:ok, count} = Storage.cleanup_orphaned()
      assert count >= 1
      refute File.exists?(orphan_path)
    end
  end
end
