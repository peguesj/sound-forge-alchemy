defmodule SoundForgeWeb.Live.Components.PerformanceSetViewComponent do
  @moduledoc """
  LiveComponent that renders the assembled loops from a completed AlchemySet
  as playable pad cards, suitable for loading into a DJ deck.
  """
  use SoundForgeWeb, :live_component

  @impl true
  def render(assigns) do
    loops = get_in(assigns, [:alchemy_set, :performance_set, "loops"]) || []

    assigns = assign(assigns, :loops, loops)

    ~H"""
    <div class="card bg-base-200 shadow">
      <div class="card-body">
        <div class="flex items-center justify-between mb-3">
          <h2 class="card-title text-base">Performance Set</h2>
          <span class="text-xs text-base-content/50">
            <%= length(@loops) %> loop<%= if length(@loops) != 1, do: "s", else: "" %>
          </span>
        </div>

        <p :if={length(@loops) == 0} class="text-sm text-base-content/50 italic">
          No loops assembled yet. Run the alchemy pipeline first.
        </p>

        <div :if={length(@loops) > 0} class="grid grid-cols-4 gap-2">
          <%= for {loop, idx} <- Enum.with_index(@loops) do %>
            <div class="bg-base-300 rounded-lg p-2 text-center hover:bg-primary/20 transition-colors cursor-pointer">
              <div class="text-2xl mb-1">&#9654;</div>
              <div class="text-xs font-mono truncate" title={loop["path"] || ""}>
                Pad <%= idx + 1 %>
              </div>
              <div :if={loop["stem"]} class="text-xs text-base-content/50 mt-0.5">
                <%= loop["stem"] %>
              </div>
              <div :if={loop["duration_ms"]} class="text-xs text-base-content/40">
                <%= Float.round((loop["duration_ms"] || 0) / 1000.0, 1) %>s
              </div>
            </div>
          <% end %>
        </div>

        <div :if={length(@loops) > 0} class="card-actions justify-end mt-4">
          <.link
            href={~p"/alchemy/#{@alchemy_set.id}/download"}
            class="btn btn-outline btn-sm"
          >
            Download ZIP
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
