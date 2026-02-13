defmodule SoundForgeWeb.API.AnalysisController do
  @moduledoc """
  Controller for audio analysis operations.
  Creates analysis jobs and enqueues Oban workers.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music

  action_fallback SoundForgeWeb.API.FallbackController

  @valid_analysis_types ~w(full tempo key spectral energy)

  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    if not File.exists?(file_path) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Audio file not found: #{Path.basename(file_path)}"})
    else
      analysis_type = Map.get(params, "type", "full")

      if analysis_type in @valid_analysis_types do
        create_analysis(conn, file_path, analysis_type, Map.get(params, "track_id"))
      else
        conn
        |> put_status(:bad_request)
        |> json(%{
          error:
            "Invalid analysis type: #{analysis_type}. Valid types: #{Enum.join(@valid_analysis_types, ", ")}"
        })
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "file_path parameter is required"})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, job} <- fetch_analysis_job(id),
         :ok <- authorize_job(conn, job) do
      json(conn, %{
        success: true,
        job_id: job.id,
        status: to_string(job.status),
        progress: job.progress || 0,
        type: get_in(job.results || %{}, ["type"]) || "full",
        result: job.results
      })
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "Access denied"})
      :error -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  defp create_analysis(conn, file_path, analysis_type, track_id) do
    features = type_to_features(analysis_type)
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

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to create analysis job"})
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

  defp fetch_analysis_job(id) do
    job = Music.get_analysis_job!(id) |> SoundForge.Repo.preload(track: [])
    {:ok, job}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
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

  defp get_user_id(conn) do
    case conn.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end
end
