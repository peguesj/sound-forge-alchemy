defmodule SoundForgeWeb.API.AnalysisController do
  @moduledoc """
  Controller for audio analysis operations.
  """
  use SoundForgeWeb, :controller

  action_fallback SoundForgeWeb.API.FallbackController

  @doc """
  POST /api/analysis/analyze
  Starts an audio analysis job.
  """
  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    analysis_type = Map.get(params, "type", "full")

    case start_analysis_job(file_path, analysis_type) do
      {:ok, job} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          job_id: job.id,
          status: job.status,
          type: get_in(job.results, ["type"]) || Map.get(job.results || %{}, :type, analysis_type)
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
    |> json(%{error: "file_path parameter is required"})
  end

  @doc """
  GET /api/analysis/job/:id
  Gets the status and results of an analysis job.
  """
  def show(conn, %{"id" => id}) do
    case get_analysis_job(id) do
      {:ok, job} ->
        json(conn, %{
          success: true,
          job_id: job.id,
          status: job.status,
          progress: job.progress,
          type: get_in(job.results, ["type"]) || Map.get(job.results || %{}, :type, "full"),
          result: job.results
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

  # Private helpers
  defp start_analysis_job(file_path, analysis_type) do
    if Code.ensure_loaded?(SoundForge.Jobs.Analysis) do
      SoundForge.Jobs.Analysis.create_job(file_path, analysis_type)
    else
      # Stub response
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         type: analysis_type,
         file_path: file_path
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         type: analysis_type,
         file_path: file_path
       }}
  end

  defp get_analysis_job(id) do
    if Code.ensure_loaded?(SoundForge.Jobs.Analysis) do
      SoundForge.Jobs.Analysis.get_job(id)
    else
      # Stub response
      {:ok,
       %{
         id: id,
         status: "completed",
         progress: 100,
         type: "full",
         result: %{
           tempo: 120.5,
           key: "C",
           mode: "major",
           time_signature: "4/4",
           duration_ms: 180_000,
           loudness: -8.5,
           energy: 0.75,
           danceability: 0.68,
           acousticness: 0.12,
           instrumentalness: 0.85,
           liveness: 0.10,
           valence: 0.60,
           sections: [
             %{start: 0, end: 30_000, label: "intro"},
             %{start: 30_000, end: 90_000, label: "verse"},
             %{start: 90_000, end: 150_000, label: "chorus"},
             %{start: 150_000, end: 180_000, label: "outro"}
           ]
         }
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         id: id,
         status: "completed",
         progress: 100,
         type: "full",
         result: %{
           tempo: 120.5,
           key: "C",
           mode: "major",
           time_signature: "4/4",
           duration_ms: 180_000,
           loudness: -8.5,
           energy: 0.75,
           danceability: 0.68,
           acousticness: 0.12,
           instrumentalness: 0.85,
           liveness: 0.10,
           valence: 0.60,
           sections: [
             %{start: 0, end: 30_000, label: "intro"},
             %{start: 30_000, end: 90_000, label: "verse"},
             %{start: 90_000, end: 150_000, label: "chorus"},
             %{start: 150_000, end: 180_000, label: "outro"}
           ]
         }
       }}
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
