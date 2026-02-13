defmodule SoundForgeWeb.API.ProcessingController do
  @moduledoc """
  Controller for audio processing operations (stem separation).
  Creates processing jobs and enqueues Oban workers.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Audio.DemucsPort
  alias SoundForge.Music

  action_fallback SoundForgeWeb.API.FallbackController

  @available_models [
    %{
      name: "htdemucs",
      description: "Hybrid Transformer Demucs - 4 stems (vocals, drums, bass, other)",
      stems: 4
    },
    %{
      name: "htdemucs_ft",
      description: "Fine-tuned Hybrid Transformer Demucs - 4 stems",
      stems: 4
    },
    %{
      name: "htdemucs_6s",
      description: "Hybrid Transformer Demucs - 6 stems",
      stems: 6
    },
    %{
      name: "mdx_extra",
      description: "MDX-Net Extra - 4 stems",
      stems: 4
    }
  ]

  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    model = Map.get(params, "model", "htdemucs")
    track_id = Map.get(params, "track_id")

    case DemucsPort.validate_model(model) do
      :ok ->
        # Create a track if not provided
        track_id = track_id || create_placeholder_track(file_path)

        case Music.create_processing_job(%{track_id: track_id, model: model, status: :queued}) do
          {:ok, job} ->
            %{
              "track_id" => track_id,
              "job_id" => job.id,
              "file_path" => file_path,
              "model" => model
            }
            |> SoundForge.Jobs.ProcessingWorker.new()
            |> Oban.insert()

            conn
            |> put_status(:created)
            |> json(%{
              success: true,
              job_id: job.id,
              status: to_string(job.status),
              model: model
            })

          {:error, _changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Failed to create processing job"})
        end

      {:error, {:invalid_model, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid model: #{model}"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "file_path parameter is required"})
  end

  def show(conn, %{"id" => id}) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, job} <- fetch_processing_job(id),
         :ok <- authorize_job(conn, job) do
      json(conn, %{
        success: true,
        job_id: job.id,
        status: to_string(job.status),
        progress: job.progress || 0,
        model: job.model || "htdemucs",
        result: job.options
      })
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "Access denied"})
      :error -> conn |> put_status(:not_found) |> json(%{error: "Job not found"})
    end
  end

  def models(conn, _params) do
    json(conn, %{success: true, models: @available_models})
  end

  defp create_placeholder_track(file_path) do
    title = file_path |> Path.basename() |> Path.rootname()

    case Music.create_track(%{title: title}) do
      {:ok, track} -> track.id
      _ -> nil
    end
  end

  defp fetch_processing_job(id) do
    job = Music.get_processing_job!(id) |> SoundForge.Repo.preload(track: [])
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
