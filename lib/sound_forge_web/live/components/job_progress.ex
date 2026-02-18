defmodule SoundForgeWeb.Components.JobProgress do
  @moduledoc """
  Components for rendering pipeline and job progress indicators.
  """
  use Phoenix.Component

  @stages [:download, :processing, :analysis]

  attr :pipeline, :map, required: true
  attr :track_title, :string, default: "Track"
  attr :class, :string, default: ""

  def pipeline_progress(assigns) do
    assigns = assign(assigns, :stages, @stages)

    ~H"""
    <div class={["bg-gray-800 rounded-lg p-4", @class]}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-medium text-white truncate mr-2">{@track_title}</h3>
        <span class={["text-xs px-2 py-0.5 rounded-full", overall_badge_class(@pipeline)]}>
          {overall_status(@pipeline)}
        </span>
      </div>

      <div class="space-y-2">
        <div :for={stage <- @stages} class="flex items-center gap-3">
          <div class={["w-2 h-2 rounded-full shrink-0", stage_dot_class(@pipeline, stage)]}></div>
          <span class="text-xs text-gray-400 w-20 shrink-0">{stage_label(stage)}</span>
          <div class="flex-1 bg-gray-700 rounded-full h-1.5">
            <div
              class={[
                "h-1.5 rounded-full transition-all duration-500",
                stage_bar_class(@pipeline, stage)
              ]}
              style={"width: #{stage_progress(@pipeline, stage)}%"}
            >
            </div>
          </div>
          <span :if={!stage_failed?(@pipeline, stage)} class="text-xs text-gray-500 w-8 text-right">
            {stage_progress(@pipeline, stage)}%
          </span>
          <button
            :if={stage_failed?(@pipeline, stage)}
            phx-click="retry_pipeline"
            phx-value-track-id={@pipeline[:track_id] || ""}
            phx-value-stage={stage}
            aria-label={"Retry #{stage_label(stage)} stage"}
            class="text-xs text-red-400 hover:text-red-300 underline shrink-0"
          >
            Retry
          </button>
        </div>
      </div>
    </div>
    """
  end

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

  defp stage_progress(pipeline, stage) do
    case Map.get(pipeline, stage) do
      %{progress: p} -> p
      _ -> 0
    end
  end

  defp stage_dot_class(pipeline, stage) do
    case Map.get(pipeline, stage) do
      %{status: :completed} -> "bg-green-400"
      %{status: :failed} -> "bg-red-400"
      %{status: s} when s in [:downloading, :processing] -> "bg-purple-400 animate-pulse"
      _ -> "bg-gray-600"
    end
  end

  defp stage_bar_class(pipeline, stage) do
    case Map.get(pipeline, stage) do
      %{status: :completed} -> "bg-green-500"
      %{status: :failed} -> "bg-red-500"
      %{status: s} when s in [:downloading, :processing] -> "bg-purple-500"
      _ -> "bg-gray-600"
    end
  end

  defp overall_status(pipeline) do
    triggered = Enum.filter(@stages, &Map.has_key?(pipeline, &1))
    statuses = Enum.map(triggered, &Map.get(pipeline, &1))

    cond do
      Enum.any?(statuses, &match?(%{status: :failed}, &1)) ->
        "Failed"

      triggered != [] and Enum.all?(statuses, &match?(%{status: :completed}, &1)) ->
        "Complete"

      Enum.any?(statuses, fn
        %{status: s} when s in [:downloading, :processing] -> true
        _ -> false
      end) ->
        "Processing"

      true ->
        "Queued"
    end
  end

  defp overall_badge_class(pipeline) do
    triggered = Enum.filter(@stages, &Map.has_key?(pipeline, &1))
    statuses = Enum.map(triggered, &Map.get(pipeline, &1))

    cond do
      Enum.any?(statuses, &match?(%{status: :failed}, &1)) ->
        "bg-red-900 text-red-300"

      triggered != [] and Enum.all?(statuses, &match?(%{status: :completed}, &1)) ->
        "bg-green-900 text-green-300"

      true ->
        "bg-purple-900 text-purple-300"
    end
  end

  defp stage_failed?(pipeline, stage) do
    match?(%{status: :failed}, Map.get(pipeline, stage))
  end

  defp stage_label(:download), do: "Download"
  defp stage_label(:processing), do: "Separate"
  defp stage_label(:analysis), do: "Analyze"
end
