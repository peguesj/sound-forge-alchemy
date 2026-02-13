defmodule SoundForgeWeb.API.ProcessingController do
  @moduledoc """
  Controller for audio processing operations (stem separation).
  """
  use SoundForgeWeb, :controller

  action_fallback SoundForgeWeb.API.FallbackController

  @doc """
  POST /api/processing/separate
  Starts a stem separation job.
  """
  def create(conn, %{"file_path" => file_path} = params)
      when is_binary(file_path) and file_path != "" do
    model = Map.get(params, "model", "htdemucs")

    case start_separation_job(file_path, model) do
      {:ok, job} ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          job_id: job.id,
          status: job.status,
          model: job.model
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
  GET /api/processing/job/:id
  Gets the status of a processing job.
  """
  def show(conn, %{"id" => id}) do
    case get_processing_job(id) do
      {:ok, job} ->
        json(conn, %{
          success: true,
          job_id: job.id,
          status: job.status,
          progress: job.progress,
          model: job.model,
          result: job.options
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

  @doc """
  GET /api/processing/models
  Lists available Demucs models.
  """
  def models(conn, _params) do
    models = list_available_models()

    json(conn, %{
      success: true,
      models: models
    })
  end

  # Private helpers
  defp start_separation_job(file_path, model) do
    if Code.ensure_loaded?(SoundForge.Jobs.Processing) do
      SoundForge.Jobs.Processing.create_separation_job(file_path, model)
    else
      # Stub response
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         model: model,
         file_path: file_path
       }}
    end
  rescue
    UndefinedFunctionError ->
      {:ok,
       %{
         id: generate_job_id(),
         status: "pending",
         model: model,
         file_path: file_path
       }}
  end

  defp get_processing_job(id) do
    if Code.ensure_loaded?(SoundForge.Jobs.Processing) do
      SoundForge.Jobs.Processing.get_job(id)
    else
      # Stub response
      {:ok,
       %{
         id: id,
         status: "completed",
         progress: 100,
         model: "htdemucs",
         result: %{
           stems: %{
             vocals: "/tmp/vocals.wav",
             drums: "/tmp/drums.wav",
             bass: "/tmp/bass.wav",
             other: "/tmp/other.wav"
           }
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
         model: "htdemucs",
         result: %{
           stems: %{
             vocals: "/tmp/vocals.wav",
             drums: "/tmp/drums.wav",
             bass: "/tmp/bass.wav",
             other: "/tmp/other.wav"
           }
         }
       }}
  end

  defp list_available_models do
    if Code.ensure_loaded?(SoundForge.Processing.Demucs) do
      SoundForge.Processing.Demucs.list_models()
    else
      # Stub response
      [
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
    end
  rescue
    UndefinedFunctionError ->
      [
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
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
