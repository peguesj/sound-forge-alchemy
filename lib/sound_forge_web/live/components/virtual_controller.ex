defmodule SoundForgeWeb.Live.Components.VirtualController do
  @moduledoc """
  Virtual DJ controller LiveComponent rendered below the DJ decks.

  Provides two jog wheels (one per deck) with rotational drag tracking,
  push-center cue functionality, and 8 performance pads per deck (4x2 grid)
  for hot cue triggering. All controls respond to both mouse and touch events.

  ## Jog Wheels
  - Click-drag on the outer ring to scratch/nudge the track position
  - Press and hold the center circle to cue

  ## Performance Pads
  - 4x2 grid of hot cue pads per deck
  - Active cue points display their assigned color
  - Tapping a pad triggers the corresponding cue point
  """
  use SoundForgeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-gray-900 rounded-xl p-4 mt-4 border border-gray-700/50">
      <h3 class="text-xs text-gray-500 uppercase tracking-wider font-semibold mb-4 text-center">
        Virtual Controller
      </h3>

      <div class="grid grid-cols-2 gap-6">
        <.controller_deck
          deck_number={1}
          deck_color="cyan"
          cue_points={@deck_1_cue_points}
          myself={@myself}
        />
        <.controller_deck
          deck_number={2}
          deck_color="orange"
          cue_points={@deck_2_cue_points}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  attr :deck_number, :integer, required: true
  attr :deck_color, :string, required: true
  attr :cue_points, :list, required: true
  attr :myself, :any, required: true

  defp controller_deck(assigns) do
    indicator_color = if assigns.deck_number == 1, do: "#22d3ee", else: "#fb923c"
    assigns = assign(assigns, :indicator_color, indicator_color)

    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <span class={"text-xs font-bold tracking-wider " <>
          if(@deck_number == 1, do: "text-cyan-400", else: "text-orange-400")}>
          DECK {@deck_number}
        </span>
      </div>

      <%!-- Jog Wheel --%>
      <div class="flex justify-center">
        <div
          id={"jog-wheel-#{@deck_number}"}
          phx-hook="JogWheel"
          data-deck={@deck_number}
          class="relative w-40 h-40 touch-none select-none"
        >
          <svg viewBox="0 0 160 160" class="w-full h-full">
            <%!-- Outer ring --%>
            <circle cx="80" cy="80" r="75" fill="none" stroke="#374151" stroke-width="4" />
            <%!-- Inner guide rings --%>
            <circle cx="80" cy="80" r="65" fill="none" stroke="#1f2937" stroke-width="1" />
            <circle cx="80" cy="80" r="55" fill="none" stroke="#1f2937" stroke-width="1" />
            <circle cx="80" cy="80" r="45" fill="none" stroke="#1f2937" stroke-width="1" />
            <%!-- Platter surface --%>
            <circle cx="80" cy="80" r="70" fill="#111827" opacity="0.8" />
            <%!-- Rotation indicator line --%>
            <line
              x1="80" y1="80" x2="80" y2="15"
              stroke={@indicator_color}
              stroke-width="2"
              class="jog-indicator"
            />
            <%!-- Center cue button --%>
            <circle
              cx="80" cy="80" r="20"
              fill="#1f2937"
              stroke="#374151"
              stroke-width="2"
              class="cursor-pointer hover:fill-gray-700 jog-center"
            />
            <text
              x="80" y="84"
              text-anchor="middle"
              fill="#9ca3af"
              font-size="10"
              font-weight="bold"
            >
              CUE
            </text>
          </svg>
        </div>
      </div>

      <%!-- Performance Pads (4x2 grid) --%>
      <div class="grid grid-cols-4 gap-1.5">
        <%= for i <- 1..8 do %>
          <% cue = Enum.at(@cue_points, i - 1) %>
          <button
            phx-click="vc_trigger_cue"
            phx-value-deck={@deck_number}
            phx-value-slot={i}
            phx-target={@myself}
            style={if cue, do: "background-color: #{cue.color};", else: ""}
            class={"w-full aspect-square rounded-md text-xs font-bold transition-colors " <>
              if(cue, do: "text-white shadow-lg", else: "bg-gray-800 text-gray-500 hover:bg-gray-700")}
          >
            {i}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("vc_trigger_cue", %{"deck" => deck, "slot" => slot}, socket) do
    send(
      self(),
      {:virtual_controller, :trigger_cue,
       %{deck: String.to_integer(deck), slot: String.to_integer(slot)}}
    )

    {:noreply, socket}
  end
end
