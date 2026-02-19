defmodule SoundForgeWeb.Live.Components.ControlSurfacesSettings do
  @moduledoc "Control Surfaces settings section with OSC, MIDI, and MPC tabs."
  use Phoenix.Component

  attr :active_tab, :atom, default: :osc
  attr :osc_config, :map, default: %{port: 8000, target_host: "", target_port: 9000, enabled: false}
  attr :midi_devices, :list, default: []
  attr :mpc_devices, :list, default: []
  attr :bridge_enabled, :boolean, default: false

  def control_surfaces(assigns) do
    ~H"""
    <div class="space-y-6">
      <h2 class="text-lg font-semibold text-white">Control Surfaces</h2>

      <!-- Tab bar -->
      <div class="flex border-b border-gray-800">
        <button
          :for={tab <- [:osc, :midi, :mpc]}
          phx-click="cs_switch_tab"
          phx-value-tab={tab}
          class={"px-4 py-2 min-h-[44px] text-sm font-medium border-b-2 transition-colors " <>
            if(@active_tab == tab,
              do: "border-purple-500 text-purple-400",
              else: "border-transparent text-gray-500 hover:text-gray-300")}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- OSC Tab -->
      <div :if={@active_tab == :osc} class="space-y-4">
        <div class="flex items-center justify-between">
          <span class="text-sm text-gray-300">OSC Server</span>
          <button
            phx-click="cs_toggle_osc"
            class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors " <>
              if(@osc_config.enabled, do: "bg-purple-600", else: "bg-gray-700")}
          >
            <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform " <>
              if(@osc_config.enabled, do: "translate-x-6", else: "translate-x-1")} />
          </button>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-xs text-gray-500 mb-1">Server Port</label>
            <input
              type="number"
              value={@osc_config.port}
              phx-blur="cs_update_osc_port"
              class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm text-white"
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 mb-1">TouchOSC Target IP</label>
            <input
              type="text"
              value={@osc_config.target_host}
              placeholder="192.168.1.100"
              phx-blur="cs_update_osc_host"
              class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm text-white"
            />
          </div>
          <div>
            <label class="block text-xs text-gray-500 mb-1">TouchOSC Target Port</label>
            <input
              type="number"
              value={@osc_config.target_port}
              phx-blur="cs_update_osc_target_port"
              class="w-full bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm text-white"
            />
          </div>
        </div>

        <!-- Bridge toggle -->
        <div class="flex items-center justify-between pt-4 border-t border-gray-800">
          <div>
            <span class="text-sm text-gray-300">MIDI-OSC Bridge</span>
            <p class="text-xs text-gray-500">Sync MIDI hardware with TouchOSC</p>
          </div>
          <button
            phx-click="cs_toggle_bridge"
            class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors " <>
              if(@bridge_enabled, do: "bg-purple-600", else: "bg-gray-700")}
          >
            <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform " <>
              if(@bridge_enabled, do: "translate-x-6", else: "translate-x-1")} />
          </button>
        </div>
      </div>

      <!-- MIDI Tab -->
      <div :if={@active_tab == :midi} class="space-y-3">
        <div :for={device <- @midi_devices} class="flex items-center justify-between p-3 bg-gray-800 rounded-lg">
          <div class="flex items-center gap-3">
            <div class={"w-2.5 h-2.5 rounded-full " <> if(device.status == :connected, do: "bg-green-500", else: "bg-red-500")} />
            <div>
              <p class="text-sm text-gray-300">{device.name}</p>
              <p class="text-xs text-gray-500">{device.direction} - {device.type}</p>
            </div>
          </div>
          <button
            phx-click="cs_toggle_midi_device"
            phx-value-id={device.port_id}
            class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors " <>
              if(device.enabled, do: "bg-purple-600", else: "bg-gray-700")}
          >
            <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform " <>
              if(device.enabled, do: "translate-x-6", else: "translate-x-1")} />
          </button>
        </div>
        <p :if={@midi_devices == []} class="text-sm text-gray-500 py-4 text-center">
          No MIDI devices detected
        </p>
      </div>

      <!-- MPC Tab -->
      <div :if={@active_tab == :mpc} class="space-y-3">
        <div :for={device <- @mpc_devices} class="flex items-center justify-between p-3 bg-gray-800 rounded-lg">
          <div class="flex items-center gap-3">
            <div class="w-2.5 h-2.5 rounded-full bg-green-500" />
            <div>
              <p class="text-sm text-gray-300">{device.name}</p>
              <p class="text-xs text-gray-500">{device.app_type}</p>
            </div>
          </div>
          <select
            phx-change="cs_set_mpc_profile"
            phx-value-id={device.port_id}
            class="bg-gray-700 border border-gray-600 rounded px-2 py-1 text-sm text-white"
          >
            <option value="mpc_one">MPC One</option>
            <option value="mpc_live">MPC Live</option>
            <option value="mpc_studio_mk2">MPC Studio Mk2</option>
            <option value="mpc_app">MPC App</option>
          </select>
        </div>
        <p :if={@mpc_devices == []} class="text-sm text-gray-500 py-4 text-center">
          No MPC devices detected
        </p>
      </div>
    </div>
    """
  end

  defp tab_label(:osc), do: "OSC"
  defp tab_label(:midi), do: "MIDI"
  defp tab_label(:mpc), do: "MPC"
end
