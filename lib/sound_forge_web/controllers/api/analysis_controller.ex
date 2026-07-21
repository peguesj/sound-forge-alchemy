defmodule SoundForgeWeb.API.AnalysisController do
  @moduledoc """
  Controller for audio analysis operations.
  Creates analysis jobs and enqueues Oban workers.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music

  action_fallback SoundForgeWeb.API.FallbackController

  @valid_analysis_types ~w(full tempo key spectral energy structure loops arrangement)

  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    if File.exists?(file_path) do
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
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Audio file not found: #{Path.basename(file_path)}"})
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

    case resolve_track_id(conn, track_id, file_path) do
      {:ok, track_id} ->
        enqueue_analysis(conn, file_path, analysis_type, features, track_id)

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})

      {:error, :invalid_track} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid or missing track"})
    end
  end

  defp enqueue_analysis(conn, file_path, analysis_type, features, track_id) do
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

  defp type_to_features("full"),
    do: [
      "tempo",
      "key",
      "energy",
      "spectral",
      "mfcc",
      "chroma",
      "structure",
      "loop_points",
      "arrangement",
      "energy_curve"
    ]

  defp type_to_features("tempo"), do: ["tempo"]
  defp type_to_features("key"), do: ["key"]
  defp type_to_features("spectral"), do: ["spectral"]
  defp type_to_features("structure"), do: ["tempo", "chroma", "structure"]
  defp type_to_features("loops"), do: ["tempo", "chroma", "structure", "loop_points"]
  defp type_to_features("arrangement"), do: ["tempo", "energy", "chroma", "arrangement"]
  defp type_to_features(type), do: [type]

  defp resolve_track_id(conn, nil, file_path), do: create_placeholder_track(conn, file_path)

  defp resolve_track_id(conn, track_id, _file_path) when is_binary(track_id) do
    with {:ok, _} <- Ecto.UUID.cast(track_id),
         {:ok, track} when not is_nil(track) <- Music.get_track(track_id),
         :ok <- authorize_track(conn, track) do
      {:ok, track.id}
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :invalid_track}
    end
  end

  defp resolve_track_id(_conn, _track_id, _file_path), do: {:error, :invalid_track}

  defp create_placeholder_track(conn, file_path) do
    title = file_path |> Path.basename() |> Path.rootname()
    user_id = get_user_id(conn)

    case Music.create_track(%{title: title, user_id: user_id, source: "import"}) do
      {:ok, track} -> {:ok, track.id}
      _ -> {:error, :invalid_track}
    end
  end

  defp fetch_analysis_job(id) do
    job = Music.get_analysis_job!(id) |> SoundForge.Repo.preload(track: [])
    {:ok, job}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp authorize_job(conn, job) do
    track = job.track

    authorize_track(conn, track)
  end

  defp authorize_track(conn, track) do
    user_id = get_user_id(conn)

    if not is_nil(track) and not is_nil(user_id) and track.user_id == user_id do
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
