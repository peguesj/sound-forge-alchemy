defmodule SoundForgeWeb.Live.BigLoopyLive do
  @moduledoc """
  LiveView for the BigLoopy alchemy pipeline at /alchemy.

  Allows users to:
  - Select source tracks from their library
  - Describe a recipe (natural language prompt)
  - Trigger the BigLoopy alchemy pipeline
  - Watch real-time progress via PubSub

  Subscribes to PubSub topic "alchemy_set:{id}" for pipeline events.
  """
  use SoundForgeWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias SoundForge.Accounts
  alias SoundForge.BigLoopy
  alias SoundForge.Jobs.BigLoopyOrchestratorWorker
  alias SoundForge.Music.Track
  alias SoundForge.Repo

  @impl true
  def mount(_params, session, socket) do
    user_id = resolve_user_id(socket.assigns[:current_user], session)

    tracks =
      if user_id do
        Repo.all(from t in Track, where: t.user_id == ^user_id, order_by: [asc: t.title])
      else
        []
      end
    alchemy_sets = if user_id, do: BigLoopy.list_alchemy_sets(user_id), else: []

    socket =
      socket
      |> assign(:current_user_id, user_id)
      |> assign(:page_title, "BigLoopy — Alchemy")
      |> assign(:tracks, tracks)
      |> assign(:alchemy_sets, alchemy_sets)
      |> assign(:selected_track_ids, [])
      |> assign(:recipe_text, "")
      |> assign(:active_set, nil)
      |> assign(:pipeline_progress, %{})
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_track", %{"id" => track_id}, socket) do
    selected = socket.assigns.selected_track_ids

    updated =
      if track_id in selected do
        List.delete(selected, track_id)
      else
        [track_id | selected]
      end

    {:noreply, assign(socket, :selected_track_ids, updated)}
  end

  def handle_event("update_recipe", %{"recipe" => recipe}, socket) do
    {:noreply, assign(socket, :recipe_text, recipe)}
  end

  def handle_event("start_alchemy", _params, socket) do
    user_id = socket.assigns.current_user_id
    track_ids = socket.assigns.selected_track_ids
    recipe_text = socket.assigns.recipe_text

    if length(track_ids) == 0 do
      {:noreply, assign(socket, :error, "Select at least one track")}
    else
      case BigLoopy.create_alchemy_set(%{
             name: "Alchemy #{DateTime.utc_now() |> Calendar.strftime("%H:%M")}",
             user_id: user_id,
             source_track_ids: track_ids,
             recipe: %{"prompt" => recipe_text},
             type: "loop_set"
           }) do
        {:ok, alchemy_set} ->
          Phoenix.PubSub.subscribe(SoundForge.PubSub, "alchemy_set:#{alchemy_set.id}")

          {:ok, _job} =
            Oban.insert(BigLoopyOrchestratorWorker.new(%{"alchemy_set_id" => alchemy_set.id}))

          {:noreply,
           socket
           |> assign(:active_set, alchemy_set)
           |> assign(:pipeline_progress, %{})
           |> assign(:error, nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, :error, "Failed to create alchemy set: #{inspect(changeset.errors)}")}
      end
    end
  end

  def handle_event("load_set", %{"id" => id}, socket) do
    case BigLoopy.get_alchemy_set(id) do
      nil -> {:noreply, assign(socket, :error, "Set not found")}
      set -> {:noreply, assign(socket, :active_set, set)}
    end
  end

  @impl true
  def handle_info({:bigloopy, :pipeline_started, _id}, socket) do
    {:noreply, assign(socket, :pipeline_progress, %{status: "started"})}
  end

  def handle_info({:bigloopy, :track_progress, _id, progress}, socket) do
    updated = Map.put(socket.assigns.pipeline_progress, progress.track_id, progress)
    {:noreply, assign(socket, :pipeline_progress, updated)}
  end

  def handle_info({:bigloopy, :track_complete, _id, result}, socket) do
    updated = Map.put(socket.assigns.pipeline_progress, result.track_id, %{status: "complete", loop_paths: result.loop_paths})
    {:noreply, assign(socket, :pipeline_progress, updated)}
  end

  def handle_info({:bigloopy, :pipeline_complete, id, %{zip_path: zip_path}}, socket) do
    set = BigLoopy.get_alchemy_set(id)

    socket =
      socket
      |> assign(:active_set, set)
      |> assign(:pipeline_progress, Map.put(socket.assigns.pipeline_progress, :status, "complete"))
      |> assign(:zip_path, zip_path)

    {:noreply, socket}
  end

  def handle_info({:bigloopy, :pipeline_error, _id, %{reason: reason}}, socket) do
    {:noreply, assign(socket, :error, "Pipeline error: #{inspect(reason)}")}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_user_id(%{id: id}, _session) when is_integer(id), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 py-8 space-y-8">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">BigLoopy — Alchemy Pipeline</h1>
        <.link navigate={~p"/"} class="btn btn-ghost btn-sm">← Dashboard</.link>
      </div>

      <%!-- Error --%>
      <div :if={@error} class="alert alert-error">
        <span><%= @error %></span>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left: Track selector --%>
        <div class="lg:col-span-1 card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-base">Source Tracks</h2>
            <p class="text-xs text-base-content/60 mb-2">Select tracks to include in the alchemy pipeline.</p>
            <ul class="space-y-1 max-h-64 overflow-y-auto">
              <%= for track <- @tracks do %>
                <li>
                  <label class="flex items-center gap-2 cursor-pointer hover:bg-base-300 rounded px-2 py-1">
                    <input
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      phx-click="toggle_track"
                      phx-value-id={track.id}
                      checked={track.id in @selected_track_ids}
                    />
                    <span class="text-sm truncate flex-1"><%= track.title || track.artist %></span>
                  </label>
                </li>
              <% end %>
            </ul>
            <p class="text-xs text-base-content/40 mt-2"><%= length(@selected_track_ids) %> selected</p>
          </div>
        </div>

        <%!-- Center: Recipe + controls --%>
        <div class="lg:col-span-2 space-y-4">
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-base">Recipe</h2>
              <p class="text-xs text-base-content/60 mb-2">
                Describe the loop set you want. E.g. "4 bar drum loop at 120 BPM, bass groove, no vocals."
              </p>
              <form phx-change="update_recipe">
                <textarea
                  name="recipe"
                  rows="4"
                  class="textarea textarea-bordered w-full text-sm"
                  placeholder="Describe your alchemy recipe..."
                  value={@recipe_text}
                ><%= @recipe_text %></textarea>
              </form>
              <div class="card-actions justify-end mt-2">
                <button
                  class="btn btn-primary btn-sm"
                  phx-click="start_alchemy"
                  disabled={length(@selected_track_ids) == 0}
                >
                  Start Alchemy
                </button>
              </div>
            </div>
          </div>

          <%!-- Progress --%>
          <.live_component
            :if={@active_set}
            module={SoundForgeWeb.Live.Components.BigLoopyProgressComponent}
            id="bigloopy-progress"
            alchemy_set={@active_set}
            progress={@pipeline_progress}
          />

          <%!-- Performance set view --%>
          <.live_component
            :if={@active_set && @active_set.status == "complete"}
            module={SoundForgeWeb.Live.Components.PerformanceSetViewComponent}
            id="performance-set-view"
            alchemy_set={@active_set}
          />
        </div>
      </div>

      <%!-- Previous sets --%>
      <div :if={length(@alchemy_sets) > 0} class="card bg-base-200 shadow">
        <div class="card-body">
          <h2 class="card-title text-base">Previous Alchemy Sets</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Type</th>
                  <th>Tracks</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for set <- @alchemy_sets do %>
                  <tr>
                    <td><%= set.name %></td>
                    <td class="text-xs"><%= set.type %></td>
                    <td class="text-xs"><%= length(set.source_track_ids) %></td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        set.status == "complete" && "badge-success",
                        set.status == "processing" && "badge-info",
                        set.status == "error" && "badge-error",
                        set.status == "pending" && "badge-ghost"
                      ]}>
                        <%= set.status %>
                      </span>
                    </td>
                    <td>
                      <button class="btn btn-xs btn-ghost" phx-click="load_set" phx-value-id={set.id}>
                        Load
                      </button>
                      <%= if set.zip_path do %>
                        <.link href={~p"/alchemy/#{set.id}/download"} class="btn btn-xs btn-outline">
                          Download
                        </.link>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
