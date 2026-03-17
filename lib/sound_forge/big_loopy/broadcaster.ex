defmodule SoundForge.BigLoopy.Broadcaster do
  @moduledoc """
  BigLoopyBroadcaster — wraps Phoenix.PubSub for BigLoopy pipeline progress events.

  Topic format: `alchemy_set:{alchemy_set_id}`

  Events broadcast:
    - `{:bigloopy, :pipeline_started, alchemy_set_id}`
    - `{:bigloopy, :track_progress, alchemy_set_id, %{track_id: id, status: status, pct: integer}}`
    - `{:bigloopy, :track_complete, alchemy_set_id, %{track_id: id, loop_paths: [String.t()]}}`
    - `{:bigloopy, :pipeline_complete, alchemy_set_id, %{zip_path: String.t()}}`
    - `{:bigloopy, :pipeline_error, alchemy_set_id, %{reason: term()}}`
  """

  @pubsub SoundForge.PubSub

  @doc "Returns the PubSub topic for an AlchemySet."
  @spec topic(binary()) :: String.t()
  def topic(alchemy_set_id), do: "alchemy_set:#{alchemy_set_id}"

  @doc "Broadcasts a pipeline started event."
  @spec broadcast_started(binary()) :: :ok | {:error, term()}
  def broadcast_started(alchemy_set_id) do
    broadcast(alchemy_set_id, {:bigloopy, :pipeline_started, alchemy_set_id})
  end

  @doc "Broadcasts a per-track progress event."
  @spec broadcast_track_progress(binary(), map()) :: :ok | {:error, term()}
  def broadcast_track_progress(alchemy_set_id, progress) do
    broadcast(alchemy_set_id, {:bigloopy, :track_progress, alchemy_set_id, progress})
  end

  @doc "Broadcasts a per-track completion event."
  @spec broadcast_track_complete(binary(), map()) :: :ok | {:error, term()}
  def broadcast_track_complete(alchemy_set_id, result) do
    broadcast(alchemy_set_id, {:bigloopy, :track_complete, alchemy_set_id, result})
  end

  @doc "Broadcasts a pipeline completion event with the ZIP path."
  @spec broadcast_complete(binary(), String.t()) :: :ok | {:error, term()}
  def broadcast_complete(alchemy_set_id, zip_path) do
    broadcast(alchemy_set_id, {:bigloopy, :pipeline_complete, alchemy_set_id, %{zip_path: zip_path}})
  end

  @doc "Broadcasts a pipeline error event."
  @spec broadcast_error(binary(), term()) :: :ok | {:error, term()}
  def broadcast_error(alchemy_set_id, reason) do
    broadcast(alchemy_set_id, {:bigloopy, :pipeline_error, alchemy_set_id, %{reason: reason}})
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp broadcast(alchemy_set_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(alchemy_set_id), message)
  end
end
