defmodule SoundForgeWeb.Live.Components.StemMixer do
  @moduledoc "Touch-optimized stem mixer with vertical faders."
  use Phoenix.Component

  @stem_colors %{
    vocals: "bg-blue-500",
    drums: "bg-red-500",
    bass: "bg-green-500",
    melody: "bg-purple-500",
    other: "bg-amber-500"
  }

  attr :stems, :list, default: []
  attr :volumes, :map, default: %{}

  def stem_mixer(assigns) do
    ~H"""
    <div
      id="stem-mixer"
      phx-hook="StemMixerHook"
      class="flex items-end justify-center gap-2 sm:gap-4 p-4 landscape-mode:h-screen"
    >
      <div
        :for={{stem, idx} <- Enum.with_index(@stems, 1)}
        data-fader={idx}
        data-value={Map.get(@volumes, idx, 0.75)}
        class="relative flex flex-col items-center cursor-pointer select-none"
      >
        <!-- Fader track -->
        <div class="relative w-[60px] min-w-[60px] h-48 sm:h-64 landscape-mode:h-[60vh] bg-gray-800 rounded-lg overflow-hidden">
          <!-- Fill -->
          <div
            data-fader-fill
            class={"absolute bottom-0 left-0 right-0 rounded-b-lg opacity-80 " <> stem_color(stem)}
            style={"height: #{(Map.get(@volumes, idx, 0.75)) * 100}%"}
          />
          <!-- Thumb -->
          <div
            data-fader-thumb
            class="absolute left-1 right-1 h-2 bg-white rounded-full shadow-lg"
            style={"bottom: #{(Map.get(@volumes, idx, 0.75)) * 100}%"}
          />
        </div>
        <!-- Mute/Solo buttons -->
        <div class="flex gap-1 mt-2">
          <button
            phx-click="stem_mute"
            phx-value-stem={idx}
            class="w-[48px] h-[48px] min-w-[48px] min-h-[48px] rounded text-xs font-bold bg-gray-800 hover:bg-red-900 text-gray-400 hover:text-red-300 transition-colors"
          >
            M
          </button>
          <button
            phx-click="stem_solo"
            phx-value-stem={idx}
            class="w-[48px] h-[48px] min-w-[48px] min-h-[48px] rounded text-xs font-bold bg-gray-800 hover:bg-amber-900 text-gray-400 hover:text-amber-300 transition-colors"
          >
            S
          </button>
        </div>
        <!-- Label -->
        <span class="mt-1 text-xs text-gray-400 truncate max-w-[60px]">
          {stem_label(stem)}
        </span>
      </div>
    </div>
    """
  end

  defp stem_color(%{type: type}), do: Map.get(@stem_colors, type, "bg-gray-500")
  defp stem_color(%{name: _}), do: "bg-purple-500"
  defp stem_color(_), do: "bg-gray-500"

  defp stem_label(%{name: name}), do: name
  defp stem_label(%{type: type}), do: Atom.to_string(type) |> String.capitalize()
  defp stem_label(_), do: "Stem"
end
