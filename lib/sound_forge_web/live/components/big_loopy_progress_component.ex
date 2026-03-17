defmodule SoundForgeWeb.Live.Components.BigLoopyProgressComponent do
  @moduledoc """
  LiveComponent that shows real-time per-track pipeline progress for a BigLoopy AlchemySet.
  """
  use SoundForgeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow">
      <div class="card-body">
        <h2 class="card-title text-base">Pipeline Progress</h2>

        <div class="flex items-center gap-2 mb-3">
          <span class={[
            "badge",
            @alchemy_set.status == "complete" && "badge-success",
            @alchemy_set.status == "processing" && "badge-info badge-outline",
            @alchemy_set.status == "error" && "badge-error",
            @alchemy_set.status == "pending" && "badge-ghost"
          ]}>
            <%= @alchemy_set.status %>
          </span>
          <span class="text-sm text-base-content/60"><%= @alchemy_set.name %></span>
        </div>

        <ul :if={map_size(@progress) > 0} class="space-y-2">
          <%= for {track_id, prog} <- @progress, is_binary(track_id) do %>
            <li class="flex items-center gap-3">
              <div class="flex-1">
                <div class="text-xs font-mono text-base-content/60 truncate w-32"><%= String.slice(track_id, 0, 8) %>...</div>
                <div class="w-full bg-base-300 rounded-full h-1.5 mt-1">
                  <div
                    class="bg-primary h-1.5 rounded-full transition-all duration-300"
                    style={"width: #{Map.get(prog, :pct, 0)}%"}
                  ></div>
                </div>
              </div>
              <span class={[
                "badge badge-sm shrink-0",
                Map.get(prog, :status) == "complete" && "badge-success",
                Map.get(prog, :status) == "extracting" && "badge-info",
                Map.get(prog, :status) == "started" && "badge-ghost",
                true && ""
              ]}>
                <%= Map.get(prog, :status, "queued") %>
              </span>
            </li>
          <% end %>
        </ul>

        <p :if={map_size(@progress) == 0} class="text-sm text-base-content/50 italic">
          Waiting for pipeline to start...
        </p>
      </div>
    </div>
    """
  end
end
