defmodule SoundForgeWeb.API.ProcessingController do
  @moduledoc """
  Controller for audio processing operations (stem separation).
  Creates processing jobs and enqueues Oban workers.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music
  alias SoundForge.Audio.DemucsPort

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

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: inspect(changeset.errors)})
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
    case Ecto.UUID.cast(id) do
      {:ok, _} ->
        try do
          job = Music.get_processing_job!(id)

          json(conn, %{
            success: true,
            job_id: job.id,
            status: to_string(job.status),
            progress: job.progress || 0,
            model: job.model || "htdemucs",
            result: job.options
          })
        rescue
          Ecto.NoResultsError ->
            conn |> put_status(:not_found) |> json(%{error: "Job not found"})
        end

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Job not found"})
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
end
