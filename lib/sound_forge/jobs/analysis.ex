defmodule SoundForge.Jobs.Analysis do
  @moduledoc """
  Context module for managing audio analysis jobs.

  Wraps the Music context's AnalysisJob schema and provides
  a higher-level interface for the analysis controller.
  """

  alias SoundForge.Music
  alias SoundForge.Repo

  @doc """
  Creates a new analysis job.

  Returns `{:ok, job}` or `{:error, reason}`.
  """
  @spec create_job(String.t(), String.t()) :: {:ok, struct()} | {:error, term()}
  def create_job(file_path, analysis_type) when is_binary(file_path) and is_binary(analysis_type) do
    with {:ok, track} <- find_or_create_track_for_file(file_path) do
      Music.create_analysis_job(%{
        track_id: track.id,
        status: :queued,
        results: %{type: analysis_type, file_path: file_path}
      })
    end
  end

  @doc """
  Gets an analysis job by ID.

  Returns `{:ok, job}` or `{:error, :not_found}`.
  """
  @spec get_job(String.t()) :: {:ok, struct()} | {:error, :not_found}
  def get_job(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} ->
        case Repo.get(Music.AnalysisJob, id) do
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
