defmodule SoundForgeWeb.Live.SampleLibraryLive do
  @moduledoc """
  LiveView for browsing and searching the user's Sample Library.

  Route: /samples
  Features:
    - Left sidebar: list of SamplePacks with click-to-filter
    - Main area: sample file list with search bar and BPM/key filters
    - In-browser audio preview via SamplePreview JS hook
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.SampleLibrary
  alias SoundForge.Accounts

  @impl true
  def mount(_params, session, socket) do
    user_id = resolve_user_id(socket.assigns[:current_user], session)

    packs = SampleLibrary.list_packs(user_id)
    files = SampleLibrary.search_files(user_id, %{limit: 50})

    current_scope = socket.assigns[:current_scope]

    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(SoundForge.PubSub, "midi:actions")
    end

    socket =
      socket
      |> assign(:page_title, "Sample Library — SFA")
      |> assign(:current_user_id, user_id)
      |> assign(:current_scope, current_scope)
      |> assign(:nav_tab, :samples)
      |> assign(:nav_context, :all_tracks)
      |> assign(:midi_devices, [])
      |> assign(:midi_bpm, nil)
      |> assign(:midi_transport, :stopped)
      |> assign(:pipelines, %{})
      |> assign(:refreshing_midi, false)
      |> assign(:packs, packs)
      |> assign(:selected_pack_id, nil)
      |> assign(:search_query, "")
      |> assign(:bpm_min, nil)
      |> assign(:bpm_max, nil)
      |> assign(:key_filter, "")
      |> assign(:category_filter, "")
      |> assign(:midi_active_file_id, nil)
      |> stream(:files, files)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pack_id = Map.get(params, "pack_id")

    socket =
      socket
      |> assign(:selected_pack_id, pack_id)
      |> reload_files()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_pack", %{"id" => pack_id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_pack_id, pack_id)
     |> reload_files()}
  end

  def handle_event("clear_pack", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_pack_id, nil)
     |> reload_files()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, q)
     |> reload_files()}
  end

  def handle_event("filter_bpm", %{"bpm_min" => min, "bpm_max" => max}, socket) do
    bpm_min = parse_float(min)
    bpm_max = parse_float(max)

    {:noreply,
     socket
     |> assign(:bpm_min, bpm_min)
     |> assign(:bpm_max, bpm_max)
     |> reload_files()}
  end

  def handle_event("filter_key", %{"key" => key}, socket) do
    {:noreply,
     socket
     |> assign(:key_filter, key)
     |> reload_files()}
  end

  def handle_event("filter_category", %{"category" => cat}, socket) do
    {:noreply,
     socket
     |> assign(:category_filter, cat)
     |> reload_files()}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp reload_files(socket) do
    user_id = socket.assigns.current_user_id

    filters =
      %{limit: 100}
      |> maybe_put(:query, socket.assigns.search_query)
      |> maybe_put(:pack_id, socket.assigns.selected_pack_id)
      |> maybe_put(:bpm_min, socket.assigns.bpm_min)
      |> maybe_put(:bpm_max, socket.assigns.bpm_max)
      |> maybe_put(:key, socket.assigns.key_filter)
      |> maybe_put(:category, socket.assigns.category_filter)

    files = SampleLibrary.search_files(user_id, filters)
    stream(socket, :files, files, reset: true)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_float(""), do: nil
  defp parse_float(nil), do: nil

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp resolve_user_id(%{id: id}, _session) when is_integer(id), do: id

  defp resolve_user_id(_, session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _} <- Accounts.get_user_by_session_token(token) do
      user.id
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # MIDI action handlers — universal transport controls
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:midi_action, :play, _params}, socket) do
    {:noreply, push_event(socket, "sample_preview_play", %{})}
  end

  def handle_info({:midi_action, :stop, _params}, socket) do
    {:noreply, push_event(socket, "sample_preview_stop", %{})}
  end

  def handle_info({:midi_action, :next_track, _params}, socket) do
    {:noreply, push_event(socket, "sample_preview_next", %{})}
  end

  def handle_info({:midi_action, :prev_track, _params}, socket) do
    {:noreply, push_event(socket, "sample_preview_prev", %{})}
  end

  def handle_info({:midi_action, _action, _params}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-950 text-gray-100 overflow-hidden">
      <SoundForgeWeb.Live.Components.AppHeader.app_header
        nav_tab={:samples}
        nav_context={@nav_context}
        current_scope={@current_scope}
        current_user_id={@current_user_id}
        midi_devices={@midi_devices}
        midi_bpm={@midi_bpm}
        midi_transport={@midi_transport}
        pipelines={@pipelines}
        refreshing_midi={@refreshing_midi}
      />
      <%!-- Main content --%>
      <div class="flex flex-1 overflow-hidden">
      <%!-- Left sidebar: pack list --%>
      <aside class="w-64 shrink-0 border-r border-base-300 p-4 overflow-y-auto">
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">Sample Packs</h2>
        <ul class="space-y-1">
          <li>
            <button
              phx-click="clear_pack"
              class={["w-full text-left px-3 py-2 rounded text-sm",
                      if(is_nil(@selected_pack_id), do: "bg-primary/20 text-primary font-medium", else: "hover:bg-base-200")]}
            >
              All Packs
            </button>
          </li>
          <%= for pack <- @packs do %>
            <li>
              <button
                phx-click="select_pack"
                phx-value-id={pack.id}
                class={["w-full text-left px-3 py-2 rounded text-sm",
                        if(@selected_pack_id == pack.id, do: "bg-primary/20 text-primary font-medium", else: "hover:bg-base-200")]}
              >
                <span class="block truncate"><%= pack.name %></span>
                <span class="text-xs text-base-content/50"><%= pack.total_files %> files · <%= pack.source %></span>
              </button>
            </li>
          <% end %>
        </ul>
      </aside>

      <%!-- Main area --%>
      <main class="flex-1 flex flex-col overflow-hidden">
        <%!-- Filter bar --%>
        <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-6 py-3 flex flex-wrap gap-3 items-center">
          <form phx-change="search" class="flex-1 min-w-48">
            <input
              type="text"
              name="q"
              value={@search_query}
              placeholder="Search samples..."
              class="input input-bordered input-sm w-full"
            />
          </form>

          <form phx-change="filter_bpm" class="flex gap-2 items-center">
            <input type="number" name="bpm_min" value={@bpm_min} placeholder="BPM min" class="input input-bordered input-sm w-24" step="0.1" />
            <span class="text-base-content/40">–</span>
            <input type="number" name="bpm_max" value={@bpm_max} placeholder="BPM max" class="input input-bordered input-sm w-24" step="0.1" />
          </form>

          <form phx-change="filter_key">
            <select name="key" class="select select-bordered select-sm">
              <option value="">All Keys</option>
              <%= for key <- ~w(C Cm D Dm E Em F Fm G Gm A Am B Bm) do %>
                <option value={key} selected={@key_filter == key}><%= key %></option>
              <% end %>
            </select>
          </form>

          <form phx-change="filter_category">
            <select name="category" class="select select-bordered select-sm">
              <option value="">All Categories</option>
              <%= for cat <- ~w(drums bass synths vocals loops sfx misc) do %>
                <option value={cat} selected={@category_filter == cat}><%= String.capitalize(cat) %></option>
              <% end %>
            </select>
          </form>
        </div>

        <%!-- File list --%>
        <div class="flex-1 overflow-y-auto px-6 py-4">
          <table class="table table-sm w-full">
            <thead>
              <tr class="text-xs text-base-content/50 uppercase">
                <th class="w-8"></th>
                <th>Name</th>
                <th>BPM</th>
                <th>Key</th>
                <th>Category</th>
                <th>Duration</th>
                <th>Size</th>
              </tr>
            </thead>
            <tbody id="sample-files" phx-update="stream">
              <%= for {dom_id, file} <- @streams.files do %>
                <tr id={dom_id} class={[
                  "hover:bg-base-200/50 group transition-colors",
                  if(@midi_active_file_id == file.id, do: "bg-primary/10 ring-1 ring-inset ring-primary/30", else: "")
                ]}>
                  <td class="w-8">
                    <%!-- Play button: always visible (dimmed), full opacity on hover — Serato/Rekordbox pattern --%>
                    <button
                      class="btn btn-ghost btn-xs opacity-40 group-hover:opacity-100 transition-opacity"
                      phx-hook="SamplePreview"
                      id={"preview-#{file.id}"}
                      data-file-path={file.file_path}
                      title={"Preview: #{file.name}"}
                    >
                      &#9654;
                    </button>
                  </td>
                  <td class="font-mono text-xs truncate max-w-xs" title={file.name}><%= file.name %></td>
                  <td class="text-xs font-mono tabular-nums text-cyan-500/80"><%= format_bpm(file.bpm) %></td>
                  <td class="text-xs font-medium text-purple-400/80"><%= file.key || "—" %></td>
                  <td class="text-xs"><%= file.category || "—" %></td>
                  <td class="text-xs tabular-nums text-gray-500"><%= format_duration(file.duration_ms) %></td>
                  <td class="text-xs tabular-nums text-gray-600"><%= format_size(file.file_size) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </main>
      </div><%!-- /flex flex-1 overflow-hidden --%>
    </div><%!-- /flex flex-col h-screen --%>
    """
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  defp format_bpm(nil), do: "—"
  defp format_bpm(bpm), do: "#{Float.round(bpm * 1.0, 1)}"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) do
    secs = div(ms, 1000)
    min = div(secs, 60)
    sec = rem(secs, 60)
    :io_lib.format("~2..0B:~2..0B", [min, sec]) |> IO.chardata_to_string()
  end

  defp format_size(nil), do: "—"

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_size(bytes) when bytes < 1_048_576 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end

  defp format_size(bytes) do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb} MB"
  end
end
