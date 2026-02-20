defmodule SoundForgeWeb.PracticeLive do
  @moduledoc "Melodics practice dashboard showing session history and recommendations."
  use SoundForgeWeb, :live_view

  alias SoundForge.Integrations.Melodics
  alias SoundForge.Integrations.Melodics.PracticeAdapter

  @impl true
  def mount(_params, session, socket) do
    user_id = resolve_user_id(socket, session)
    stats = safe_practice_stats(user_id)
    sessions = safe_list_sessions(user_id)

    socket =
      socket
      |> assign(:page_title, "Practice")
      |> assign(:current_user_id, user_id)
      |> assign(:stats, stats)
      |> assign(:sessions, sessions)
      |> assign(:importing, false)
      |> assign(:detail_tab, :stems)

    {:ok, socket}
  end

  @impl true
  def handle_event("import_sessions", _params, socket) do
    socket = assign(socket, :importing, true)
    user_id = socket.assigns.current_user_id

    case Melodics.import_sessions(user_id) do
      {:ok, count} ->
        stats = safe_practice_stats(user_id)
        sessions = safe_list_sessions(user_id)

        {:noreply,
         socket
         |> assign(:importing, false)
         |> assign(:stats, stats)
         |> assign(:sessions, sessions)
         |> put_flash(:info, "Imported #{count} practice sessions")}

      {:error, :melodics_not_found} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Melodics data directory not found. Is Melodics installed?")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:importing, false)
         |> put_flash(:error, "Failed to import practice sessions")}
    end
  end

  def handle_event("switch_detail_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :detail_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-6 space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-white">Practice Dashboard</h1>
        <button
          phx-click="import_sessions"
          disabled={@importing}
          class="px-4 py-2 min-h-[44px] bg-purple-600 hover:bg-purple-500 disabled:bg-gray-700 text-white rounded-lg text-sm font-medium transition-colors"
        >
          <%= if @importing do %>
            <span class="flex items-center gap-2">
              <svg class="animate-spin w-4 h-4" viewBox="0 0 24 24" fill="none">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
              Importing...
            </span>
          <% else %>
            Import from Melodics
          <% end %>
        </button>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <p class="text-xs text-gray-500 uppercase">Total Sessions</p>
          <p class="text-2xl font-bold text-white mt-1">{@stats.total_sessions}</p>
        </div>
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <p class="text-xs text-gray-500 uppercase">Avg Accuracy</p>
          <p class="text-2xl font-bold text-white mt-1">
            {format_accuracy(@stats.avg_accuracy)}
          </p>
        </div>
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <p class="text-xs text-gray-500 uppercase">Avg BPM</p>
          <p class="text-2xl font-bold text-white mt-1">
            {format_bpm(@stats.avg_bpm)}
          </p>
        </div>
        <div class="bg-gray-900 rounded-lg p-4 border border-gray-800">
          <p class="text-xs text-gray-500 uppercase">This Week</p>
          <p class="text-2xl font-bold text-white mt-1">{@stats.sessions_this_week}</p>
          <!-- Weekly streak dots -->
          <div class="flex gap-1 mt-2">
            <div :for={day <- 1..7} class={"w-3 h-3 rounded-full " <> if(day <= @stats.sessions_this_week, do: "bg-green-500", else: "bg-gray-700")} />
          </div>
        </div>
      </div>

      <!-- BPM Trend Sparkline placeholder -->
      <div :if={@stats.bpm_trend != []} class="bg-gray-900 rounded-lg p-4 border border-gray-800">
        <h3 class="text-sm font-semibold text-gray-400 mb-2">BPM Progression</h3>
        <div class="flex items-end gap-1 h-16">
          <div
            :for={bpm <- @stats.bpm_trend}
            class="bg-purple-500 rounded-t flex-1 min-w-[4px]"
            style={"height: #{bpm_bar_height(bpm, @stats.bpm_trend)}%"}
          />
        </div>
      </div>

      <!-- Stem Recommendations -->
      <div :if={@stats[:stem_suggestions] && @stats.stem_suggestions != []} class="bg-gray-900 rounded-lg p-4 border border-gray-800">
        <h3 class="text-sm font-semibold text-gray-400 mb-3">Stem Recommendations</h3>
        <div class="space-y-2">
          <div :for={{category, difficulty, meta} <- @stats.stem_suggestions} class="flex items-center justify-between text-sm">
            <span class="text-gray-300 capitalize">{category}</span>
            <div class="flex items-center gap-2">
              <span class={"px-2 py-0.5 rounded text-xs font-medium " <> difficulty_badge(difficulty)}>
                {difficulty}
              </span>
              <span class="text-gray-500 text-xs">{format_accuracy(meta.avg_accuracy)}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Session History Table -->
      <div class="bg-gray-900 rounded-lg border border-gray-800 overflow-hidden">
        <h3 class="text-sm font-semibold text-gray-400 p-4 border-b border-gray-800">Session History</h3>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="text-xs text-gray-500 uppercase bg-gray-900/50">
              <tr>
                <th class="px-4 py-3 text-left">Date</th>
                <th class="px-4 py-3 text-left">Lesson</th>
                <th class="px-4 py-3 text-right">Accuracy</th>
                <th class="px-4 py-3 text-right">BPM</th>
                <th class="px-4 py-3 text-left">Instrument</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-800">
              <tr :for={session <- @sessions} class="text-gray-300 hover:bg-gray-800/50">
                <td class="px-4 py-3">{format_date(session.practiced_at)}</td>
                <td class="px-4 py-3 font-medium">{session.lesson_name}</td>
                <td class="px-4 py-3 text-right">{format_accuracy(session.accuracy)}</td>
                <td class="px-4 py-3 text-right">{session.bpm || "-"}</td>
                <td class="px-4 py-3 capitalize">{session.instrument || "-"}</td>
              </tr>
              <tr :if={@sessions == []} class="text-gray-500">
                <td colspan="5" class="px-4 py-8 text-center">
                  No practice sessions yet. Click "Import from Melodics" to get started.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # -- Helpers --

  defp resolve_user_id(socket, _session) do
    case socket.assigns do
      %{current_scope: %{user: %{id: id}}} -> id
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end

  defp safe_practice_stats(nil), do: empty_stats()

  defp safe_practice_stats(user_id) do
    try do
      PracticeAdapter.practice_stats(user_id)
    catch
      :exit, _ -> empty_stats()
    end
  end

  defp safe_list_sessions(nil), do: []

  defp safe_list_sessions(user_id) do
    try do
      Melodics.list_sessions(user_id, limit: 30)
    catch
      :exit, _ -> []
    end
  end

  defp empty_stats do
    %{
      total_sessions: 0,
      avg_accuracy: nil,
      avg_bpm: nil,
      instruments: [],
      sessions_this_week: 0,
      bpm_trend: [],
      stem_suggestions: []
    }
  end

  defp format_accuracy(nil), do: "-"
  defp format_accuracy(v), do: "#{Float.round(v * 1.0, 1)}%"

  defp format_bpm(nil), do: "-"
  defp format_bpm(v) when is_float(v), do: "#{round(v)}"
  defp format_bpm(v), do: "#{v}"

  defp format_date(nil), do: "-"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(_), do: "-"

  defp bpm_bar_height(_bpm, []), do: 0

  defp bpm_bar_height(bpm, trend) do
    max_bpm = Enum.max(trend)
    if max_bpm > 0, do: round(bpm / max_bpm * 100), else: 0
  end

  defp difficulty_badge(:simple), do: "bg-blue-900/50 text-blue-300"
  defp difficulty_badge(:matched), do: "bg-green-900/50 text-green-300"
  defp difficulty_badge(:complex), do: "bg-amber-900/50 text-amber-300"
  defp difficulty_badge(_), do: "bg-gray-800 text-gray-400"
end
