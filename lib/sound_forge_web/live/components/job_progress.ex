defmodule SoundForgeWeb.Components.JobProgress do
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
              class={["h-1.5 rounded-full transition-all duration-500", stage_bar_class(@pipeline, stage)]}
              style={"width: #{stage_progress(@pipeline, stage)}%"}
            >
            </div>
          </div>
          <span class="text-xs text-gray-500 w-8 text-right">{stage_progress(@pipeline, stage)}%</span>
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
    cond do
      Enum.any?(@stages, fn s -> match?(%{status: :failed}, Map.get(pipeline, s)) end) ->
        "Failed"

      match?(%{status: :completed}, Map.get(pipeline, :analysis)) ->
        "Complete"

      Enum.any?(@stages, fn s ->
        match?(%{status: s} when s in [:downloading, :processing], Map.get(pipeline, s))
      end) ->
        "Processing"

      true ->
        "Queued"
    end
  end

  defp overall_badge_class(pipeline) do
    cond do
      Enum.any?(@stages, fn s -> match?(%{status: :failed}, Map.get(pipeline, s)) end) ->
        "bg-red-900 text-red-300"

      match?(%{status: :completed}, Map.get(pipeline, :analysis)) ->
        "bg-green-900 text-green-300"

      true ->
        "bg-purple-900 text-purple-300"
    end
  end

  defp stage_label(:download), do: "Download"
  defp stage_label(:processing), do: "Separate"
  defp stage_label(:analysis), do: "Analyze"
end
