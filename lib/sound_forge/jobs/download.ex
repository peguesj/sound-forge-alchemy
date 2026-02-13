defmodule SoundForge.Jobs.Download do
  @moduledoc """
  Context module for managing download jobs.

  Wraps the Music context's DownloadJob schema and provides
  a higher-level interface for the download controller.
  """

  alias SoundForge.Music
  alias SoundForge.Repo

  @doc """
  Creates a new download job for the given Spotify URL.

  First finds or creates a track from the URL, then creates
  a DownloadJob record and enqueues the Oban worker.

  Returns `{:ok, job}` or `{:error, reason}`.
  """
  @spec create_job(String.t()) :: {:ok, map()} | {:error, term()}
  def create_job(url) when is_binary(url) do
    with {:ok, track} <- find_or_create_track(url),
         {:ok, job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
      enqueue_worker(job, track, url)
      {:ok, job}
    end
  end

  @doc """
  Gets a download job by ID.

  Returns `{:ok, job}` or `{:error, :not_found}`.
  """
  @spec get_job(String.t()) :: {:ok, struct()} | {:error, :not_found}
  def get_job(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} ->
        case Repo.get(Music.DownloadJob, id) do
          nil -> {:error, :not_found}
          job -> {:ok, job}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp find_or_create_track(url) do
    case Repo.get_by(Music.Track, spotify_url: url) do
      nil -> Music.create_track(%{title: "Pending download", spotify_url: url})
      track -> {:ok, track}
    end
  end

  defp enqueue_worker(job, track, url) do
    %{
      track_id: track.id,
      spotify_url: url,
      quality: "320k",
      job_id: job.id
    }
    |> SoundForge.Jobs.DownloadWorker.new()
    |> Oban.insert()
  end
end
