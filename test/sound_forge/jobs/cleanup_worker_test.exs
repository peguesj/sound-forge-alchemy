defmodule SoundForge.Jobs.CleanupWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.CleanupWorker
  alias SoundForge.Storage

  import SoundForge.MusicFixtures

  @tmp_dir System.tmp_dir!() |> Path.join("sfa_cleanup_test")

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

  describe "perform/1" do
    test "runs cleanup successfully with empty storage" do
      Storage.ensure_directories!()
      job = %Oban.Job{args: %{}}
      assert :ok = CleanupWorker.perform(job)
    end

    test "runs cleanup and removes orphaned files" do
      Storage.ensure_directories!()

      # Create orphaned files (not referenced in DB)
      orphan_path = Path.join(Storage.downloads_path(), "orphan.mp3")
      File.write!(orphan_path, "orphaned audio")

      job = %Oban.Job{args: %{}}
      assert :ok = CleanupWorker.perform(job)

      refute File.exists?(orphan_path)
    end

    test "preserves files referenced by stems" do
      Storage.ensure_directories!()

      # Create file referenced by a stem record
      stem_file = Path.join(Storage.stems_path(), "vocals.wav")
      File.write!(stem_file, "stem audio data")

      track = track_fixture()
      pj = processing_job_fixture(%{track_id: track.id})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: stem_file})

      # Also create an orphaned file
      orphan_file = Path.join(Storage.stems_path(), "orphan.wav")
      File.write!(orphan_file, "orphaned stem")

      job = %Oban.Job{args: %{}}
      assert :ok = CleanupWorker.perform(job)

      # Referenced file should remain
      assert File.exists?(stem_file)
      # Orphaned file should be deleted
      refute File.exists?(orphan_file)
    end

    test "preserves files referenced by download jobs" do
      Storage.ensure_directories!()

      # Create file referenced by a download job
      dl_file = Path.join(Storage.downloads_path(), "track.mp3")
      File.write!(dl_file, "downloaded audio")

      track = track_fixture()
      download_job_fixture(%{track_id: track.id, output_path: dl_file})

      job = %Oban.Job{args: %{}}
      assert :ok = CleanupWorker.perform(job)

      assert File.exists?(dl_file)
    end
  end

  describe "Storage.cleanup_orphaned/0" do
    test "returns count of deleted files" do
      Storage.ensure_directories!()

      File.write!(Path.join(Storage.downloads_path(), "orphan1.mp3"), "data1")
      File.write!(Path.join(Storage.downloads_path(), "orphan2.mp3"), "data2")

      assert {:ok, 2} = Storage.cleanup_orphaned()
    end

    test "returns 0 when no orphans exist" do
      Storage.ensure_directories!()
      assert {:ok, 0} = Storage.cleanup_orphaned()
    end

    test "returns 0 when storage directory does not exist" do
      Application.put_env(:sound_forge, :storage_path, "/nonexistent/path/#{System.unique_integer()}")
      assert {:ok, 0} = Storage.cleanup_orphaned()
    end

    test "handles nested directories" do
      Storage.ensure_directories!()

      nested_dir = Path.join(Storage.stems_path(), "nested")
      File.mkdir_p!(nested_dir)
      File.write!(Path.join(nested_dir, "orphan.wav"), "nested orphan")

      assert {:ok, 1} = Storage.cleanup_orphaned()
      refute File.exists?(Path.join(nested_dir, "orphan.wav"))
    end
  end
end
