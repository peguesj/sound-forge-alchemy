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

    if File.exists?(file_path) do
      create_processing(conn, file_path, model, track_id)
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

  defp create_processing(conn, file_path, model, track_id) do
    case DemucsPort.validate_model(model) do
      :ok ->
        case resolve_track_id(conn, track_id, file_path) do
          {:ok, track_id} ->
            enqueue_processing(conn, file_path, model, track_id)

          {:error, :forbidden} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})

          {:error, :invalid_track} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "Invalid or missing track"})
        end

      {:error, {:invalid_model, _}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid model: #{model}"})
    end
  end

  defp enqueue_processing(conn, file_path, model, track_id) do
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

  defp fetch_processing_job(id) do
    job = Music.get_processing_job!(id) |> SoundForge.Repo.preload(track: [])
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
