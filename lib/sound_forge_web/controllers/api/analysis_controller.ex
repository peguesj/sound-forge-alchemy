defmodule SoundForgeWeb.API.AnalysisController do
  @moduledoc """
  Controller for audio analysis operations.
  Creates analysis jobs and enqueues Oban workers.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music

  action_fallback SoundForgeWeb.API.FallbackController

  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    analysis_type = Map.get(params, "type", "full")
    track_id = Map.get(params, "track_id")
    features = type_to_features(analysis_type)

    # Create a track if not provided
    track_id = track_id || create_placeholder_track(file_path)

    case Music.create_analysis_job(%{
           track_id: track_id,
           status: :queued,
           results: %{type: analysis_type, file_path: file_path}
         }) do
      {:ok, job} ->
        %{
          "track_id" => track_id,
          "job_id" => job.id,
          "file_path" => file_path,
          "features" => features
        }
        |> SoundForge.Jobs.AnalysisWorker.new()
        |> Oban.insert()

        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          job_id: job.id,
          status: to_string(job.status),
          type: analysis_type
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(changeset.errors)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "file_path parameter is required"})
  end

  def show(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, _} ->
        try do
          job = Music.get_analysis_job!(id)

          json(conn, %{
            success: true,
            job_id: job.id,
            status: to_string(job.status),
            progress: job.progress || 0,
            type: get_in(job.results || %{}, ["type"]) || "full",
            result: job.results
          })
        rescue
          Ecto.NoResultsError ->
            conn |> put_status(:not_found) |> json(%{error: "Job not found"})
        end

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  defp type_to_features("full"), do: ["tempo", "key", "energy", "spectral"]
  defp type_to_features("tempo"), do: ["tempo"]
  defp type_to_features("key"), do: ["key"]
  defp type_to_features("spectral"), do: ["spectral"]
  defp type_to_features(type), do: [type]

  defp create_placeholder_track(file_path) do
    title = file_path |> Path.basename() |> Path.rootname()

    case Music.create_track(%{title: title}) do
      {:ok, track} -> track.id
      _ -> nil
    end
  end
end
