defmodule SoundForge.Jobs.Processing do
  @moduledoc """
  Context module for managing stem separation processing jobs.

  Wraps the Music context's ProcessingJob schema and provides
  a higher-level interface for the processing controller.
  """

  alias SoundForge.Music
  alias SoundForge.Repo

  @doc """
  Creates a new stem separation job.

  Returns `{:ok, job}` or `{:error, reason}`.
  """
  @spec create_separation_job(String.t(), String.t()) :: {:ok, struct()} | {:error, term()}
  def create_separation_job(file_path, model) when is_binary(file_path) and is_binary(model) do
    # Find a track associated with this file path, or create a placeholder
    with {:ok, track} <- find_or_create_track_for_file(file_path) do
      Music.create_processing_job(%{
        track_id: track.id,
        model: model,
        status: :queued,
        options: %{file_path: file_path, model: model}
      })
    end
  end

  @doc """
  Gets a processing job by ID.

  Returns `{:ok, job}` or `{:error, :not_found}`.
  """
  @spec get_job(String.t()) :: {:ok, struct()} | {:error, :not_found}
  def get_job(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} ->
        case Repo.get(Music.ProcessingJob, id) do
          nil -> {:error, :not_found}
          job -> {:ok, job}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp find_or_create_track_for_file(file_path) do
    title = Path.basename(file_path, Path.extname(file_path))
    Music.create_track(%{title: title})
  end
end
