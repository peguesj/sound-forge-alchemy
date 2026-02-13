defmodule SoundForgeWeb.JobChannel do
  use SoundForgeWeb, :channel

  @impl true
  def join("jobs:" <> job_id, _payload, socket) do
    # Subscribe to PubSub for this job
    Phoenix.PubSub.subscribe(SoundForge.PubSub, "jobs:#{job_id}")
    {:ok, assign(socket, :job_id, job_id)}
  end

  # Handle PubSub broadcasts and relay to channel
  @impl true
  def handle_info({:job_progress, payload}, socket) do
    push(socket, "job:progress", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:job_completed, payload}, socket) do
    push(socket, "job:completed", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:job_failed, payload}, socket) do
    push(socket, "job:failed", payload)
    {:noreply, socket}
  end
end
