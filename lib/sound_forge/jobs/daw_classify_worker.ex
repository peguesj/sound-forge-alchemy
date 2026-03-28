defmodule SoundForge.Jobs.DawClassifyWorker do
  @moduledoc """
  Oban worker that classifies all `unknown`-typed track lanes in a DAW project.

  Triggered automatically by `DAW.add_track/2` after a new lane is inserted.
  Iterates every `DawProjectTrack` in the project whose `track_type` is
  `"unknown"`, loads the associated `Music.Track` with its analysis results,
  runs `TrackClassifier.classify/1`, and persists the result via
  `DAW.update_track_type/2`.

  ## Job Arguments

    - `"project_id"` - UUID of the `DawProject` to classify

  ## Retry behaviour

  Up to 3 attempts (default Oban exponential back-off).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias SoundForge.{DAW, Repo}
  alias SoundForge.Daw.DawProjectTrack
  alias SoundForge.DAW.TrackClassifier

  import Ecto.Query, warn: false

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    project = DAW.get_project!(project_id)

    project.project_tracks
    |> Enum.filter(&(&1.track_type == "unknown"))
    |> Enum.each(fn %DawProjectTrack{audio_file: audio_file} = lane ->
      if audio_file do
        track_with_analysis = Repo.preload(audio_file, :analysis_results)

        case TrackClassifier.classify(track_with_analysis) do
          {:ok, type, _confidence} ->
            DAW.update_track_type(lane, %{type: type, manual: false})

          _error ->
            :ok
        end
      end
    end)

    :ok
  end
end
