defmodule SoundForgeWeb.API.DownloadController do
  @moduledoc """
  Controller for track download operations.
  Creates tracks from Spotify URLs and enqueues download jobs.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music

  action_fallback SoundForgeWeb.API.FallbackController

  def create(conn, %{"url" => url}) when is_binary(url) and url != "" do
    user_id = get_user_id(conn)

    with {:ok, metadata} <- SoundForge.Spotify.fetch_metadata(url),
         {:ok, track} <- create_track(metadata, url, user_id),
         {:ok, job} <- Music.create_download_job(%{track_id: track.id, status: :queued}) do
      # Enqueue the download worker
      %{
        "track_id" => track.id,
        "spotify_url" => url,
        "quality" => "320k",
        "job_id" => job.id
      }
      |> SoundForge.Jobs.DownloadWorker.new()
      |> Oban.insert()

      conn
      |> put_status(:created)
      |> json(%{
        success: true,
        job_id: job.id,
        status: to_string(job.status),
        track_id: track.id
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "url parameter is required"})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, job} <- fetch_download_job(id),
         :ok <- authorize_job(conn, job) do
      json(conn, %{
        success: true,
        job_id: job.id,
        status: to_string(job.status),
        progress: job.progress || 0,
        result: if(job.output_path, do: %{file_path: job.output_path}, else: nil)
      })
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "Access denied"})
      :error -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  defp fetch_download_job(id) do
    try do
      job = Music.get_download_job!(id) |> SoundForge.Repo.preload(:track)
      {:ok, job}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
    end
  end

  defp authorize_job(conn, job) do
    user_id = get_user_id(conn)
    track = job.track

    if is_nil(track) or is_nil(track.user_id) or track.user_id == user_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp create_track(metadata, url, user_id) do
    attrs = %{
      title: metadata["name"] || "Unknown",
      artist: extract_artist(metadata),
      album: get_in(metadata, ["album", "name"]),
      album_art_url: extract_album_art(metadata),
      spotify_id: metadata["id"],
      spotify_url: url,
      duration: metadata["duration_ms"],
      user_id: user_id
    }

    Music.create_track(attrs)
  end

  defp extract_artist(%{"artists" => [%{"name" => name} | _]}), do: name
  defp extract_artist(_), do: nil

  defp extract_album_art(%{"album" => %{"images" => [%{"url" => url} | _]}}), do: url
  defp extract_album_art(_), do: nil

  defp get_user_id(conn) do
    case conn.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end
end
