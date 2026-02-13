defmodule SoundForgeWeb.Components.JobProgress do
  use Phoenix.Component

  attr :job, :map, required: true
  attr :class, :string, default: ""

  def job_progress(assigns) do
    ~H"""
    <div class={["mb-3 bg-gray-800 rounded-lg p-3", @class]}>
      <div class="flex justify-between text-sm">
        <span class="text-gray-300">{@job.status}</span>
        <span class="text-purple-400">{@job.progress}%</span>
      </div>
      <div class="mt-2 bg-gray-700 rounded-full h-2">
        <div class="bg-purple-500 h-2 rounded-full transition-all" style={"width: #{@job.progress}%"}>
        </div>
      </div>
    </div>
    """
  end
end
