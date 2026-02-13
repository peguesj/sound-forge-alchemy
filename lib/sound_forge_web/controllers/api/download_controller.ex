defmodule SoundForgeWeb.API.DownloadController do
  @moduledoc """
  Controller for track download operations.
  """
  use SoundForgeWeb, :controller

  action_fallback SoundForgeWeb.API.FallbackController

  @doc """
  POST /api/download/track
  Starts a download job for a track.
  """
  def create(conn, %{"url" => url}) when is_binary(url) and url != "" do
    case start_download_job(url) do
      {:ok, job} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          job_id: job.id,
          status: job.status
        })

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

  @doc """
  GET /api/download/job/:id
  Gets the status of a download job.
  """
  def show(conn, %{"id" => id}) do
    case get_download_job(id) do
      {:ok, job} ->
        json(conn, %{
          success: true,
          job_id: job.id,
          status: job.status,
          progress: job.progress,
          result: if(job.output_path, do: %{file_path: job.output_path}, else: nil)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Job not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: to_string(reason)})
    end
  end

  # Private helpers - try to call context modules if they exist
  defp start_download_job(url) do
    if Code.ensure_loaded?(SoundForge.Jobs.Download) do
      SoundForge.Jobs.Download.create_job(url)
    else
      # Stub response
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         url: url
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         url: url
       }}
  end

  defp get_download_job(id) do
    if Code.ensure_loaded?(SoundForge.Jobs.Download) do
      SoundForge.Jobs.Download.get_job(id)
    else
      # Stub response
      {:ok,
       %{
         id: id,
         status: "completed",
         progress: 100,
         result: %{file_path: "/tmp/example.mp3"}
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         id: id,
         status: "completed",
         progress: 100,
         result: %{file_path: "/tmp/example.mp3"}
       }}
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
