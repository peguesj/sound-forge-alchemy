defmodule SoundForge.Jobs.SpliceImportWorker do
  @moduledoc """
  Oban worker that imports a local audio file from the Splice library
  into the SFA track database.

  Creates a Track with source='splice' and infers sample_type from duration:
  - duration < 8s  → one_shot
  - duration >= 8s → loop

  Enqueues AnalysisWorker after import to extract features + drum events.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    priority: 3

  import Ecto.Query, only: [from: 2]

  alias SoundForge.Music
  alias SoundForge.Repo

  require Logger

  @audio_mime_types %{
    ".wav" => "audio/wav",
    ".mp3" => "audio/mpeg",
    ".aif" => "audio/aiff",
    ".aiff" => "audio/aiff",
    ".flac" => "audio/flac"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_path" => file_path}}) do
    Logger.metadata(worker: "SpliceImportWorker", file_path: file_path)
    Logger.info("[SpliceImportWorker] Importing #{Path.basename(file_path)}")

    with :ok <- validate_file(file_path),
         {:ok, meta} <- extract_metadata(file_path),
         {:ok, track} <- create_track(file_path, meta) do
      Logger.info("[SpliceImportWorker] Imported track #{track.id}: #{track.title}")
      enqueue_analysis(track)
      add_to_source_playlist(track)
      :ok
    else
      {:error, :already_imported} ->
        Logger.debug("[SpliceImportWorker] Already imported: #{file_path}")
        :ok

      {:error, reason} ->
        Logger.warning("[SpliceImportWorker] Failed to import #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private

  defp validate_file(path) do
    if File.regular?(path), do: :ok, else: {:error, :file_not_found}
  end

  defp extract_metadata(file_path) do
    # Extract title from filename (strip extension and clean up)
    basename = Path.basename(file_path, Path.extname(file_path))
    title = basename |> String.replace(~r/[-_]/, " ") |> String.trim()

    # Use ffprobe to get duration if available, otherwise estimate from file size
    duration_ms = probe_duration_ms(file_path)
    sample_type = if duration_ms && duration_ms < 8_000, do: "one_shot", else: "loop"

    {:ok,
     %{
       title: title,
       duration_ms: duration_ms,
       sample_type: sample_type,
       file_path: file_path
     }}
  end

  defp probe_duration_ms(file_path) do
    case System.cmd("ffprobe", [
           "-v", "quiet",
           "-print_format", "json",
           "-show_format",
           file_path
         ], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"format" => %{"duration" => duration_str}}} ->
            case Float.parse(duration_str) do
              {seconds, _} -> round(seconds * 1000)
              :error -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp create_track(file_path, meta) do
    # Check for existing track with same file path (stored as spotify_url for compatibility)
    case Repo.get_by(SoundForge.Music.Track, spotify_url: "file://#{file_path}") do
      %SoundForge.Music.Track{} ->
        {:error, :already_imported}

      nil ->
        attrs = %{
          title: meta.title,
          source: "splice",
          sample_type: meta.sample_type,
          duration_ms: meta.duration_ms,
          # Store local path as spotify_url for file serving compatibility
          spotify_url: "file://#{file_path}",
          # Use a system user_id of 0 for globally imported samples
          # In multi-user deployments, scanners would be per-user
          user_id: get_system_user_id()
        }

        Music.create_track(attrs)
    end
  end

  defp enqueue_analysis(track) do
    case Oban.insert(
           SoundForge.Jobs.AnalysisWorker.new(%{
             "track_id" => track.id,
             "file_path" => String.replace(track.spotify_url || "", "file://", "")
           })
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("[SpliceImportWorker] Analysis enqueue failed: #{inspect(reason)}")
    end
  end

  defp add_to_source_playlist(track) do
    user_id = track.user_id
    playlist_type = if track.sample_type == "one_shot", do: "manual", else: "loop_collection"

    case Music.create_or_get_source_playlist(user_id, "splice", playlist_type) do
      {:ok, playlist} ->
        Music.add_track_to_playlist(playlist.id, track.id)

      {:error, _} ->
        :ok
    end
  end

  defp get_system_user_id do
    # Return the first admin user or 1 as fallback
    case SoundForge.Repo.one(
           from u in SoundForge.Accounts.User,
           order_by: [asc: u.id],
           limit: 1,
           select: u.id
         ) do
      nil -> 1
      id -> id
    end
  end
end
