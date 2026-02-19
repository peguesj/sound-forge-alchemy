defmodule SoundForgeWeb.Live.Components.PadAssignment do
  @moduledoc "MPC Pad Assignment grid with drag-and-drop stem mapping."
  use Phoenix.Component

  @pad_count 16
  @stem_colors %{
    "vocals" => "bg-blue-600",
    "drums" => "bg-red-600",
    "bass" => "bg-green-600",
    "other" => "bg-purple-600"
  }

  attr :assignments, :map, default: %{}
  attr :stems, :list, default: []

  def pad_grid(assigns) do
    assigns = assign(assigns, :pads, 1..@pad_count |> Enum.to_list())

    ~H"""
    <div id="pad-assignment" phx-hook="PadAssignHook" class="flex flex-col md:flex-row gap-6">
      <!-- Pad Grid: 4x4 -->
      <div class="grid grid-cols-4 gap-2 flex-shrink-0">
        <div
          :for={pad <- @pads}
          data-pad-drop={pad}
          class={"w-20 h-20 min-w-[44px] min-h-[44px] rounded-lg flex flex-col items-center justify-center text-xs font-bold cursor-pointer transition-all border-2 border-gray-700 " <> pad_color(@assignments, pad)}
        >
          <span class="text-white/80">Pad {pad}</span>
          <span :if={Map.get(@assignments, pad)} class="text-[10px] text-white/60 mt-1 truncate max-w-[70px]">
            {pad_stem_label(@assignments, pad)}
          </span>
          <button
            :if={Map.get(@assignments, pad)}
            phx-click="clear_pad"
            phx-value-pad={pad}
            class="mt-1 text-[9px] text-red-400 hover:text-red-300 min-w-[44px] min-h-[22px]"
          >
            Clear
          </button>
        </div>
      </div>

      <!-- Stem List (drag source) -->
      <div class="flex-1 space-y-2">
        <h3 class="text-sm font-semibold text-gray-400 mb-2">Available Stems</h3>
        <div
          :for={stem <- @stems}
          data-stem-drag={stem.id}
          class="flex items-center gap-2 px-3 py-2 bg-gray-800 rounded-lg cursor-grab active:cursor-grabbing hover:bg-gray-700 transition-colors min-h-[44px]"
        >
          <div class={"w-3 h-3 rounded-full " <> stem_dot_color(stem)} />
          <span class="text-sm text-gray-300">{stem.name || stem.type}</span>
        </div>
        <p :if={@stems == []} class="text-sm text-gray-600">No stems available. Process a track first.</p>
      </div>
    </div>
    """
  end

  defp pad_color(assignments, pad) do
    case Map.get(assignments, pad) do
      nil -> "bg-gray-800"
      %{type: type} -> Map.get(@stem_colors, to_string(type), "bg-gray-600")
      _ -> "bg-gray-600"
    end
  end

  defp pad_stem_label(assignments, pad) do
    case Map.get(assignments, pad) do
      %{name: name} -> name
      %{type: type} -> to_string(type)
      _ -> ""
    end
  end

  defp stem_dot_color(%{type: type}) do
    Map.get(@stem_colors, to_string(type), "bg-gray-500")
  end

  defp stem_dot_color(_), do: "bg-gray-500"
end
