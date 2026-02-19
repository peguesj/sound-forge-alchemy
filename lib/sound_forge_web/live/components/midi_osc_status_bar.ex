defmodule SoundForgeWeb.Live.Components.MidiOscStatusBar do
  @moduledoc "Status bar showing MIDI/OSC connection and activity status."
  use Phoenix.Component

  attr :midi_device_count, :integer, default: 0
  attr :osc_active, :boolean, default: false
  attr :touchosc_target, :string, default: nil
  attr :mpc_device_name, :string, default: nil
  attr :message_rate, :integer, default: 0
  attr :collapsed, :boolean, default: false

  def status_bar(assigns) do
    ~H"""
    <div class={"flex items-center gap-3 px-3 py-1.5 bg-gray-900/80 border-b border-gray-800 text-xs " <>
      if(@collapsed, do: "md:flex hidden", else: "flex")}>
      <!-- MIDI devices -->
      <div class="flex items-center gap-1.5" title="Connected MIDI devices">
        <svg class="w-3.5 h-3.5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2z" />
        </svg>
        <span class={"font-medium " <> if(@midi_device_count > 0, do: "text-green-400", else: "text-gray-600")}>
          {@midi_device_count}
        </span>
      </div>

      <div class="w-px h-3 bg-gray-800" />

      <!-- OSC status -->
      <div class="flex items-center gap-1.5" title="OSC server status">
        <div class={"w-2 h-2 rounded-full " <> if(@osc_active, do: "bg-green-500 animate-pulse", else: "bg-red-500")} />
        <span class="text-gray-500">OSC</span>
      </div>

      <!-- TouchOSC target -->
      <div :if={@touchosc_target} class="flex items-center gap-1.5 text-gray-500" title="TouchOSC target">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
        </svg>
        <span class="text-cyan-400/70">{@touchosc_target}</span>
      </div>

      <!-- MPC device -->
      <div :if={@mpc_device_name} class="flex items-center gap-1.5" title="MPC device">
        <span class="px-1.5 py-0.5 bg-purple-900/50 text-purple-300 rounded text-[10px] font-medium">
          {@mpc_device_name}
        </span>
      </div>

      <!-- Activity rate -->
      <div :if={@message_rate > 0} class="flex items-center gap-1 ml-auto text-gray-600" title="Messages/sec">
        <div class="flex items-end gap-px h-3">
          <div :for={i <- 1..5} class={"w-0.5 rounded-t transition-all " <>
            if(i <= activity_level(@message_rate), do: "bg-purple-500", else: "bg-gray-800")}
            style={"height: #{i * 20}%"}
          />
        </div>
        <span class="text-[10px]">{@message_rate}/s</span>
      </div>

      <!-- Collapse toggle (mobile) -->
      <button
        phx-click="toggle_status_bar"
        class="md:hidden ml-auto text-gray-600 hover:text-gray-400 min-w-[44px] min-h-[44px] flex items-center justify-center"
      >
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d={if @collapsed, do: "M19 9l-7 7-7-7", else: "M5 15l7-7 7 7"} />
        </svg>
      </button>
    </div>
    """
  end

  defp activity_level(rate) when rate > 50, do: 5
  defp activity_level(rate) when rate > 20, do: 4
  defp activity_level(rate) when rate > 10, do: 3
  defp activity_level(rate) when rate > 5, do: 2
  defp activity_level(_), do: 1
end
