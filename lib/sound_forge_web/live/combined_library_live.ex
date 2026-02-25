defmodule SoundForgeWeb.CombinedLibraryLive do
  @moduledoc """
  Platform-admin view showing ALL tracks across ALL users in a unified,
  paginated, searchable table.

  Access is restricted to `:platform_admin` and `:super_admin` roles.
  Route: GET /platform/library
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Admin

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    case check_platform_admin_access(socket) do
      :ok ->
        socket =
          socket
          |> assign(:page_title, "Platform Library")
          |> assign(:search, "")
          |> assign(:page, 1)
          |> assign(:library, %{tracks: [], total: 0, page: 1, per_page: @per_page})

        {:ok, socket}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "You do not have permission to access the platform library.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = parse_page(params["page"])
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> load_library()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/platform/library?search=#{search}&page=1")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/platform/library?search=#{socket.assigns.search}&page=#{page}"
     )}
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-4 md:p-6">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-3xl font-bold">Platform Library</h1>
          <p class="text-sm text-base-content/60 mt-1">
            All tracks across all users — platform admin view
          </p>
        </div>
        <span class="badge badge-warning badge-lg">Platform Admin</span>
      </div>

      <%!-- Search bar --%>
      <div class="mb-4">
        <form phx-submit="search" class="flex gap-3 items-end">
          <div class="form-control flex-1 max-w-md">
            <label class="label">
              <span class="label-text text-xs">Search by title, artist, or user email</span>
            </label>
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search..."
              class="input input-bordered"
              phx-debounce="300"
            />
          </div>
          <button type="submit" class="btn btn-primary">Search</button>
          <a :if={@search != ""} href="/platform/library" class="btn btn-ghost">Clear</a>
        </form>
      </div>

      <%!-- Stats --%>
      <div class="text-sm text-base-content/60 mb-3">
        Showing <%= (@library.page - 1) * @library.per_page + 1 %>–<%= min(@library.page * @library.per_page, @library.total) %> of <%= @library.total %> tracks
      </div>

      <%!-- Table --%>
      <div class="overflow-x-auto card bg-base-100 shadow-md">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Title</th>
              <th>Artist</th>
              <th>User Email</th>
              <th>Download</th>
              <th>Stems</th>
              <th>Uploaded At</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={track <- @library.tracks}>
              <td class="font-medium max-w-xs truncate">{track.title || "(untitled)"}</td>
              <td class="max-w-xs truncate">{track.artist || "—"}</td>
              <td class="font-mono text-sm">{track.user_email || "—"}</td>
              <td>
                <span class={"badge badge-sm #{download_badge(track.download_status)}"}>
                  {track.download_status || "none"}
                </span>
              </td>
              <td>
                <span class={["badge badge-sm", track.stem_count > 0 && "badge-success" || "badge-ghost"]}>
                  {track.stem_count}
                </span>
              </td>
              <td class="text-sm">
                {if track.inserted_at, do: Calendar.strftime(track.inserted_at, "%Y-%m-%d %H:%M"), else: "—"}
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={@library.tracks == []} class="py-12 text-center text-base-content/40">
          No tracks found
        </div>
      </div>

      <%!-- Pagination --%>
      <.pagination library={@library} search={@search} />
    </div>
    """
  end

  # ============================================================
  # Components
  # ============================================================

  attr :library, :map, required: true
  attr :search, :string, required: true

  defp pagination(assigns) do
    total_pages = max(1, ceil(assigns.library.total / assigns.library.per_page))
    assigns = assign(assigns, :total_pages, total_pages)

    ~H"""
    <div :if={@total_pages > 1} class="flex justify-center gap-2 mt-4">
      <button
        :if={@library.page > 1}
        class="btn btn-sm"
        phx-click="page"
        phx-value-page={@library.page - 1}
      >
        Prev
      </button>
      <span class="btn btn-sm btn-ghost no-animation">
        Page {@library.page} of {@total_pages}
      </span>
      <button
        :if={@library.page < @total_pages}
        class="btn btn-sm"
        phx-click="page"
        phx-value-page={@library.page + 1}
      >
        Next
      </button>
    </div>
    """
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp load_library(socket) do
    library =
      Admin.all_tracks_paginated(
        page: socket.assigns.page,
        per_page: @per_page,
        search: socket.assigns.search
      )

    assign(socket, :library, library)
  end

  defp check_platform_admin_access(socket) do
    role = socket.assigns[:current_scope] && socket.assigns.current_scope.role

    if role in [:platform_admin, :super_admin] do
      :ok
    else
      :error
    end
  end

  defp parse_page(nil), do: 1
  defp parse_page(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp download_badge("completed"), do: "badge-success"
  defp download_badge("running"), do: "badge-info"
  defp download_badge("failed"), do: "badge-error"
  defp download_badge("pending"), do: "badge-warning"
  defp download_badge(_), do: "badge-ghost"
end
