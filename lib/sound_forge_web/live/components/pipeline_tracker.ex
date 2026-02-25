defmodule SoundForgeWeb.Live.Components.PipelineTracker do
  @moduledoc """
  LiveComponent rendering a pipeline tracker icon in the header with an active
  pipeline count badge and a dropdown panel showing pipeline progress.

  Similar in structure to `NotificationBell`, this component displays:
    - A cog/gear icon with a badge for the count of active pipelines
    - A dropdown with active pipelines (progress bars per stage)
    - Completed pipelines grouped separately
    - Each pipeline shows track name, current stage, and progress percentage

  ## Required assigns

    - `:pipelines` - map of `%{track_id => pipeline_map}` from the parent LiveView

  ## Usage in a parent template

      <.live_component
        module={SoundForgeWeb.Live.Components.PipelineTracker}
        id="pipeline-tracker"
        pipelines={@pipelines}
      />
  """
  use SoundForgeWeb, :live_component

  @stages [:download, :processing, :analysis]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)}
  end

  @impl true
  def update(assigns, socket) do
    pipelines = assigns[:pipelines] || socket.assigns[:pipelines] || %{}

    {active, completed} = partition_pipelines(pipelines)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:active_pipelines, active)
     |> assign(:completed_pipelines, completed)
     |> assign(:active_count, length(active))
     |> assign(:total_count, map_size(pipelines))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative">
      <!-- Tracker Button -->
      <button
        type="button"
        phx-click="toggle_tracker"
        phx-target={@myself}
        aria-label={"Pipeline tracker, #{@active_count} active"}
        aria-expanded={to_string(@open)}
        aria-haspopup="true"
        class="relative p-2 text-gray-400 hover:text-white transition-colors rounded-lg hover:bg-gray-800"
      >
        <svg
          class={["w-6 h-6", if(@active_count > 0, do: "text-purple-400", else: "")]}
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z"
          />
        </svg>
        <!-- Active Count Badge -->
        <span
          :if={@active_count > 0}
          class="absolute -top-0.5 -right-0.5 flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-bold text-white bg-purple-500 rounded-full"
        >
          {badge_text(@active_count)}
        </span>
      </button>

      <!-- Dropdown Panel -->
      <div
        :if={@open}
        id={"#{@id}-dropdown"}
        phx-click-away="close_tracker"
        phx-target={@myself}
        class="absolute right-0 top-full mt-2 w-96 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 overflow-hidden"
        role="menu"
        aria-label="Pipeline tracker panel"
      >
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-gray-700">
          <h3 class="text-sm font-semibold text-white">Pipelines</h3>
          <div class="flex items-center gap-2">
            <span :if={@active_count > 0} class="text-xs text-purple-400">
              {badge_text(@active_count)} active
            </span>
            <span :if={@active_count == 0 && @total_count > 0} class="text-xs text-gray-500">
              All complete
            </span>
          </div>
        </div>

        <!-- Pipeline List -->
        <div class="max-h-96 overflow-y-auto">
          <!-- Empty State -->
          <div
            :if={@total_count == 0}
            class="px-4 py-8 text-center text-sm text-gray-500"
          >
            No active pipelines
          </div>

          <!-- Active Pipelines -->
          <div :if={@active_count > 0} class="border-b border-gray-700/50">
            <div class="px-4 py-2 bg-gray-800/50">
              <span class="text-[10px] font-semibold text-gray-500 uppercase tracking-wider">
                Active
              </span>
            </div>
            <div
              :for={{track_id, pipeline} <- @active_pipelines}
              class="px-4 py-3 border-b border-gray-700/30 last:border-0 hover:bg-gray-750/30"
            >
              <div class="flex items-center justify-between mb-2">
                <span class="text-sm font-medium text-white truncate mr-2">
                  {pipeline_track_label(track_id)}
                </span>
                <span class={["text-[10px] px-1.5 py-0.5 rounded-full", overall_badge_class(pipeline)]}>
                  {overall_status(pipeline)}
                </span>
              </div>
              <div class="space-y-1.5">
                <div :for={stage <- @stages} :if={Map.has_key?(pipeline, stage)} class="flex items-center gap-2">
                  <div class={["w-1.5 h-1.5 rounded-full shrink-0", stage_dot_class(pipeline, stage)]}></div>
                  <span class="text-[10px] text-gray-500 w-14 shrink-0">{stage_label(stage)}</span>
                  <div class="flex-1 bg-gray-700 rounded-full h-1">
                    <div
                      class={["h-1 rounded-full transition-all duration-500", stage_bar_class(pipeline, stage)]}
                      style={"width: #{stage_progress(pipeline, stage)}%"}
                    >
                    </div>
                  </div>
                  <span :if={!stage_failed?(pipeline, stage)} class="text-[10px] text-gray-500 w-7 text-right">
                    {stage_progress(pipeline, stage)}%
                  </span>
                  <button
                    :if={stage_failed?(pipeline, stage)}
                    phx-click="retry_pipeline"
                    phx-value-track-id={track_id}
                    phx-value-stage={stage}
                    aria-label={"Retry #{stage_label(stage)} stage"}
                    class="text-[10px] text-red-400 hover:text-red-300 underline shrink-0"
                  >
                    Retry
                  </button>
                </div>
              </div>
              <div class="flex justify-end mt-1.5">
                <button
                  phx-click="dismiss_pipeline"
                  phx-value-track-id={track_id}
                  class="text-[10px] text-gray-600 hover:text-gray-400 transition-colors"
                  aria-label="Dismiss pipeline"
                >
                  Dismiss
                </button>
              </div>
            </div>
          </div>

          <!-- Completed Pipelines -->
          <div :if={length(@completed_pipelines) > 0}>
            <div class="px-4 py-2 bg-gray-800/50">
              <span class="text-[10px] font-semibold text-gray-500 uppercase tracking-wider">
                Completed
              </span>
            </div>
            <div
              :for={{track_id, pipeline} <- @completed_pipelines}
              class="px-4 py-2.5 border-b border-gray-700/30 last:border-0 hover:bg-gray-750/30"
            >
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2 min-w-0">
                  <svg class="w-3.5 h-3.5 text-green-400 shrink-0" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span class="text-sm text-gray-300 truncate">
                    {pipeline_track_label(track_id)}
                  </span>
                </div>
                <button
                  phx-click="dismiss_pipeline"
                  phx-value-track-id={track_id}
                  class="text-[10px] text-gray-600 hover:text-gray-400 transition-colors ml-2 shrink-0"
                  aria-label="Dismiss completed pipeline"
                >
                  &times;
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Footer: Clear Completed -->
        <div :if={length(@completed_pipelines) > 0} class="border-t border-gray-700 px-4 py-2.5">
          <button
            type="button"
            phx-click="clear_completed"
            phx-target={@myself}
            class="w-full text-center text-xs text-purple-400 hover:text-purple-300 transition-colors font-medium"
          >
            Clear completed
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_tracker", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  @impl true
  def handle_event("close_tracker", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("clear_completed", _params, socket) do
    completed_ids = Enum.map(socket.assigns.completed_pipelines, fn {track_id, _} -> track_id end)

    Enum.each(completed_ids, fn track_id ->
      send(self(), {:dismiss_pipeline_from_tracker, track_id})
    end)

    {:noreply, socket}
  end

  # -- Private helpers --

  defp partition_pipelines(pipelines) do
    {active, completed} =
      pipelines
      |> Enum.split_with(fn {_track_id, pipeline} ->
        not pipeline_complete?(pipeline)
      end)

    {active, completed}
  end

  defp pipeline_complete?(pipeline) do
    triggered = Enum.filter(@stages, &Map.has_key?(pipeline, &1))

    triggered != [] and
      Enum.all?(triggered, fn stage ->
        match?(%{status: :completed}, Map.get(pipeline, stage))
      end)
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

  defp stage_failed?(pipeline, stage) do
    match?(%{status: :failed}, Map.get(pipeline, stage))
  end

  defp overall_status(pipeline) do
    triggered = Enum.filter(@stages, &Map.has_key?(pipeline, &1))
    statuses = Enum.map(triggered, &Map.get(pipeline, &1))

    cond do
      Enum.any?(statuses, &match?(%{status: :failed}, &1)) -> "Failed"
      triggered != [] and Enum.all?(statuses, &match?(%{status: :completed}, &1)) -> "Complete"
      Enum.any?(statuses, fn
        %{status: s} when s in [:downloading, :processing] -> true
        _ -> false
      end) -> "Processing"
      true -> "Queued"
    end
  end

  defp overall_badge_class(pipeline) do
    triggered = Enum.filter(@stages, &Map.has_key?(pipeline, &1))
    statuses = Enum.map(triggered, &Map.get(pipeline, &1))

    cond do
      Enum.any?(statuses, &match?(%{status: :failed}, &1)) -> "bg-red-900 text-red-300"
      triggered != [] and Enum.all?(statuses, &match?(%{status: :completed}, &1)) -> "bg-green-900 text-green-300"
      true -> "bg-purple-900 text-purple-300"
    end
  end

  defp stage_label(:download), do: "Download"
  defp stage_label(:processing), do: "Separate"
  defp stage_label(:analysis), do: "Analyze"

  defp pipeline_track_label(track_id) when is_binary(track_id) do
    case SoundForge.Music.get_track(track_id) do
      {:ok, %{title: title}} when is_binary(title) and title != "" -> title
      _ -> "Track #{String.slice(track_id, 0, 8)}..."
    end
  end

  defp pipeline_track_label(_), do: "Track"

  defp badge_text(count) when count > 99, do: "99+"
  defp badge_text(count), do: to_string(count)
end
