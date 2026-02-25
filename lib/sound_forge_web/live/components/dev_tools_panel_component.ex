defmodule SoundForgeWeb.Live.Components.DevToolsPanelComponent do
  @moduledoc """
  Floating bottom-right dev tools panel — only rendered in the :dev Mix environment.

  Shows:
  - Current URL / path
  - Number of assigns on the parent socket
  - Quick links to /prototype and /admin

  ## Usage in a LiveView layout (dev only)

      <%= if Mix.env() == :dev do %>
        <.live_component
          module={SoundForgeWeb.Live.Components.DevToolsPanelComponent}
          id="dev-tools-panel"
          current_path={@current_path}
          assigns_count={map_size(@__changed__ || %{})}
        />
      <% end %>
  """

  use SoundForgeWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :open, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:current_path, assigns[:current_path] || "/")
      |> assign(:assigns_count, assigns[:assigns_count] || 0)
      |> assign_new(:open, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-4 right-4 z-[9999] flex flex-col items-end gap-2">
      <%!-- Toggle button --%>
      <button
        phx-click="toggle"
        phx-target={@myself}
        class={[
          "px-3 py-1.5 rounded-full text-xs font-mono font-semibold shadow-lg transition-all border",
          if(@open,
            do: "bg-yellow-400 text-yellow-900 border-yellow-500",
            else: "bg-gray-900 text-yellow-400 border-yellow-600/50 hover:border-yellow-400"
          )
        ]}
        title="Toggle DevTools panel"
      >
        DevTools
      </button>

      <%!-- Panel --%>
      <div
        :if={@open}
        class="w-72 bg-gray-950 border border-yellow-600/40 rounded-xl shadow-2xl text-xs font-mono text-gray-200 overflow-hidden"
      >
        <%!-- Header --%>
        <div class="flex items-center justify-between px-3 py-2 bg-yellow-500/10 border-b border-yellow-600/30">
          <span class="text-yellow-400 font-semibold">DevTools Panel</span>
          <span class="text-gray-500">:dev</span>
        </div>

        <%!-- Info rows --%>
        <div class="p-3 space-y-2">
          <div class="flex justify-between">
            <span class="text-gray-500">Path</span>
            <span class="text-gray-200 truncate max-w-[160px] text-right">{@current_path}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Assigns</span>
            <span class="text-gray-200">{@assigns_count}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-500">Env</span>
            <span class="text-yellow-400">dev</span>
          </div>
        </div>

        <%!-- Quick links --%>
        <div class="px-3 pb-3 flex flex-col gap-1">
          <a
            href="/prototype"
            class="block px-2 py-1 rounded bg-yellow-500/10 hover:bg-yellow-500/20 text-yellow-300 transition-colors"
          >
            /prototype sandbox
          </a>
          <a
            href="/admin"
            class="block px-2 py-1 rounded bg-blue-500/10 hover:bg-blue-500/20 text-blue-300 transition-colors"
          >
            /admin dashboard
          </a>
          <a
            href="/admin/dev-tools"
            class="block px-2 py-1 rounded bg-purple-500/10 hover:bg-purple-500/20 text-purple-300 transition-colors"
          >
            /admin/dev-tools
          </a>
          <a
            href="/platform/library"
            class="block px-2 py-1 rounded bg-orange-500/10 hover:bg-orange-500/20 text-orange-300 transition-colors"
          >
            /platform/library
          </a>
        </div>
      </div>
    </div>
    """
  end
end
