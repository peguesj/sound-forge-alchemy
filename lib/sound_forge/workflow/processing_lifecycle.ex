defmodule SoundForge.Workflow.ProcessingLifecycle do
  @moduledoc """
  Concrete lifecycle for the SFA track processing pipeline, built on
  `SoundForge.Workflow.Lifecycle`.

      queued -> downloading -> processing -> analyzing -> completed

  `failed` is reachable from every active (non-terminal) state, and a failed
  job can be retried back to `queued`. `completed` is terminal.

  Adoption example (inside a context, before persisting a status change):

      with {:ok, new_status} <- ProcessingLifecycle.transition(track.status, :processing) do
        Music.update_track(track, %{status: new_status})
      end
  """

  use SoundForge.Workflow.Lifecycle,
    transitions: %{
      queued: [:queued, :downloading, :failed],
      downloading: [:downloading, :processing, :failed],
      processing: [:processing, :analyzing, :failed],
      analyzing: [:analyzing, :completed, :failed],
      completed: [:completed],
      failed: [:failed, :queued]
    }
end
