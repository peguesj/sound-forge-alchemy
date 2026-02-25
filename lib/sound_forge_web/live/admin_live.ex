defmodule SoundForgeWeb.AdminLive do
  @moduledoc """
  Admin dashboard LiveView with overview, users, jobs, system, analytics, and audit tabs.
  Production-grade admin panel with search, filters, bulk operations, and role management.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Admin

  @admin_tabs ~w(overview users jobs system analytics audit llm)a
  @valid_roles ~w(user pro enterprise admin super_admin platform_admin)a

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> assign(:admin_tabs, @admin_tabs)
      |> assign(:valid_roles, @valid_roles)
      |> assign(:tab, :overview)
      |> assign(:stats, Admin.system_stats())
      |> assign(:user_data, %{users: [], total: 0, page: 1, per_page: 25})
      |> assign(:user_search, "")
      |> assign(:user_role_filter, nil)
      |> assign(:user_status_filter, nil)
      |> assign(:selected_user_ids, MapSet.new())
      |> assign(:bulk_role, nil)
      |> assign(:jobs, [])
      |> assign(:storage, %{})
      |> assign(:job_filter, "all")
      |> assign(:audit_logs, [])
      |> assign(:audit_action_filter, nil)
      |> assign(:audit_search, "")
      |> assign(:registrations_by_day, [])
      |> assign(:tracks_by_day, [])
      |> assign(:pipeline, %{})
      |> assign(:llm_stats, %{total: 0, enabled: 0, healthy: 0})

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        tab when tab in ~w(overview users jobs system analytics audit llm) ->
          String.to_existing_atom(tab)

        _ ->
          :overview
      end

    socket = assign(socket, :tab, tab) |> load_tab_data()
    {:noreply, socket}
  end

  # ============================================================
  # Events
  # ============================================================

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?tab=#{tab}")}
  end

  # -- User Management Events --

  def handle_event("search_users", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:user_search, search)
      |> load_users()

    {:noreply, socket}
  end

  def handle_event("filter_users_role", %{"role" => role}, socket) do
    role_atom = if role == "", do: nil, else: String.to_existing_atom(role)

    socket =
      socket
      |> assign(:user_role_filter, role_atom)
      |> load_users()

    {:noreply, socket}
  end

  def handle_event("filter_users_status", %{"status" => status}, socket) do
    status_atom = if status == "", do: nil, else: String.to_existing_atom(status)

    socket =
      socket
      |> assign(:user_status_filter, status_atom)
      |> load_users()

    {:noreply, socket}
  end

  def handle_event("change_role", %{"id" => id, "role" => role}, socket) do
    actor_id = socket.assigns.current_scope.user.id
    role_atom = String.to_existing_atom(role)
    {:ok, _} = Admin.update_user_role(String.to_integer(id), role_atom, actor_id)
    {:noreply, load_users(socket)}
  end

  def handle_event("suspend_user", %{"id" => id}, socket) do
    actor_id = socket.assigns.current_scope.user.id
    {:ok, _} = Admin.suspend_user(String.to_integer(id), actor_id)
    {:noreply, load_users(socket)}
  end

  def handle_event("ban_user", %{"id" => id}, socket) do
    actor_id = socket.assigns.current_scope.user.id
    {:ok, _} = Admin.ban_user(String.to_integer(id), actor_id)
    {:noreply, load_users(socket)}
  end

  def handle_event("reactivate_user", %{"id" => id}, socket) do
    actor_id = socket.assigns.current_scope.user.id
    {:ok, _} = Admin.reactivate_user(String.to_integer(id), actor_id)
    {:noreply, load_users(socket)}
  end

  def handle_event("toggle_select_user", %{"id" => id}, socket) do
    user_id = String.to_integer(id)
    selected = socket.assigns.selected_user_ids

    selected =
      if MapSet.member?(selected, user_id),
        do: MapSet.delete(selected, user_id),
        else: MapSet.put(selected, user_id)

    {:noreply, assign(socket, :selected_user_ids, selected)}
  end

  def handle_event("select_all_users", _params, socket) do
    all_ids =
      socket.assigns.user_data.users
      |> Enum.map(& &1.id)
      |> MapSet.new()

    {:noreply, assign(socket, :selected_user_ids, all_ids)}
  end

  def handle_event("deselect_all_users", _params, socket) do
    {:noreply, assign(socket, :selected_user_ids, MapSet.new())}
  end

  def handle_event("bulk_change_role", %{"role" => role}, socket) do
    actor_id = socket.assigns.current_scope.user.id
    user_ids = MapSet.to_list(socket.assigns.selected_user_ids)
    role_atom = String.to_existing_atom(role)

    if length(user_ids) > 0 do
      {:ok, _count} = Admin.bulk_update_role(user_ids, role_atom, actor_id)

      socket =
        socket
        |> assign(:selected_user_ids, MapSet.new())
        |> load_users()
        |> put_flash(:info, "Updated #{length(user_ids)} users to #{role}.")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "No users selected.")}
    end
  end

  def handle_event("users_page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    socket =
      socket
      |> assign(:user_data, %{socket.assigns.user_data | page: page})
      |> load_users()

    {:noreply, socket}
  end

  # -- Job Events --

  def handle_event("filter_jobs", %{"state" => state}, socket) do
    jobs = Admin.all_jobs(state: state)
    {:noreply, assign(socket, jobs: jobs, job_filter: state)}
  end

  def handle_event("retry_job", %{"id" => id}, socket) do
    Oban.retry_job(String.to_integer(id))
    jobs = Admin.all_jobs(state: socket.assigns.job_filter)
    {:noreply, assign(socket, :jobs, jobs)}
  end

  # -- LLM Events --

  def handle_event("run_health_checks", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    count = Admin.enqueue_health_checks(user_id)

    socket =
      socket
      |> assign(:llm_stats, Admin.llm_stats())
      |> put_flash(:info, "Enqueued health checks for #{count} provider(s).")

    {:noreply, socket}
  end

  # -- Audit Events --

  def handle_event("filter_audit_action", %{"action" => action}, socket) do
    action_val = if action == "", do: nil, else: action

    socket =
      socket
      |> assign(:audit_action_filter, action_val)
      |> load_audit_logs()

    {:noreply, socket}
  end

  def handle_event("search_audit", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:audit_search, search)
      |> load_audit_logs()

    {:noreply, socket}
  end

  # ============================================================
  # Data Loading
  # ============================================================

  defp load_tab_data(%{assigns: %{tab: :overview}} = socket) do
    assign(socket, :stats, Admin.system_stats())
  end

  defp load_tab_data(%{assigns: %{tab: :users}} = socket) do
    load_users(socket)
  end

  defp load_tab_data(%{assigns: %{tab: :jobs}} = socket) do
    assign(socket, :jobs, Admin.all_jobs(state: socket.assigns.job_filter))
  end

  defp load_tab_data(%{assigns: %{tab: :system}} = socket) do
    socket
    |> assign(:storage, Admin.storage_stats())
    |> assign(:stats, Admin.system_stats())
  end

  defp load_tab_data(%{assigns: %{tab: :analytics}} = socket) do
    socket
    |> assign(:registrations_by_day, Admin.user_registrations_by_day())
    |> assign(:tracks_by_day, Admin.tracks_by_day())
    |> assign(:pipeline, Admin.pipeline_throughput())
    |> assign(:stats, Admin.system_stats())
  end

  defp load_tab_data(%{assigns: %{tab: :audit}} = socket) do
    load_audit_logs(socket)
  end

  defp load_tab_data(%{assigns: %{tab: :llm}} = socket) do
    assign(socket, :llm_stats, Admin.llm_stats())
  end

  defp load_tab_data(socket), do: socket

  defp load_users(socket) do
    opts = [
      page: socket.assigns.user_data.page,
      per_page: socket.assigns.user_data.per_page,
      search: if(socket.assigns.user_search == "", do: nil, else: socket.assigns.user_search),
      role: socket.assigns.user_role_filter,
      status: socket.assigns.user_status_filter
    ]

    assign(socket, :user_data, Admin.list_users(opts))
  end

  defp load_audit_logs(socket) do
    opts = [
      action: socket.assigns.audit_action_filter,
      search: if(socket.assigns.audit_search == "", do: nil, else: socket.assigns.audit_search)
    ]

    assign(socket, :audit_logs, Admin.list_audit_logs(opts))
  end

  # ============================================================
  # Render
  # ============================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-4 md:p-6">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-3xl font-bold">Admin Dashboard</h1>
        <span class="badge badge-outline">
          {String.capitalize(to_string(@current_scope.role))}
        </span>
      </div>

      <div class="tabs tabs-boxed mb-6">
        <button
          :for={tab <- @admin_tabs}
          class={"tab #{if @tab == tab, do: "tab-active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <%!-- Overview Tab --%>
      <div :if={@tab == :overview} class="space-y-6">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card label="Total Users" value={@stats.user_count} />
          <.stat_card label="Total Tracks" value={@stats.track_count} />
          <.stat_card label="Active Jobs" value={Map.get(@stats.oban, "executing", 0)} />
          <.stat_card label="Failed Jobs" value={Map.get(@stats.oban, "discarded", 0)} />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="card bg-base-100 shadow-md p-6">
            <h3 class="font-semibold mb-3">Users by Role</h3>
            <div :for={{role, count} <- @stats.users_by_role} class="flex justify-between py-1 border-b border-base-200 last:border-0">
              <span class="capitalize">{role}</span>
              <span class="font-mono badge badge-sm">{count}</span>
            </div>
          </div>

          <div class="card bg-base-100 shadow-md p-6">
            <h3 class="font-semibold mb-3">Users by Status</h3>
            <div :for={{status, count} <- @stats.users_by_status} class="flex justify-between py-1 border-b border-base-200 last:border-0">
              <span class={"capitalize #{status_color(status)}"}>{status}</span>
              <span class="font-mono badge badge-sm">{count}</span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Users Tab --%>
      <div :if={@tab == :users} class="space-y-4">
        <div class="flex flex-wrap gap-3 items-end">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Search</span></label>
            <input
              type="text"
              placeholder="Search by email..."
              value={@user_search}
              phx-keyup="search_users"
              phx-key="Enter"
              phx-value-search={@user_search}
              class="input input-bordered input-sm w-64"
              name="search"
              phx-debounce="300"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Role</span></label>
            <select class="select select-bordered select-sm" phx-change="filter_users_role" name="role">
              <option value="">All Roles</option>
              <option :for={role <- @valid_roles} value={role} selected={@user_role_filter == role}>
                {String.capitalize(to_string(role))}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Status</span></label>
            <select class="select select-bordered select-sm" phx-change="filter_users_status" name="status">
              <option value="">All Statuses</option>
              <option value="active" selected={@user_status_filter == :active}>Active</option>
              <option value="suspended" selected={@user_status_filter == :suspended}>Suspended</option>
              <option value="banned" selected={@user_status_filter == :banned}>Banned</option>
            </select>
          </div>

          <div class="text-sm text-base-content/60 self-end pb-2">
            {MapSet.size(@selected_user_ids)} selected of {@user_data.total} total
          </div>
        </div>

        <%!-- Bulk Actions --%>
        <div :if={MapSet.size(@selected_user_ids) > 0} class="flex gap-2 items-center bg-base-100 p-3 rounded-lg shadow-sm">
          <span class="text-sm font-medium">Bulk Actions:</span>
          <select class="select select-bordered select-xs" phx-change="bulk_change_role" name="role">
            <option value="" disabled selected>Change role to...</option>
            <option :for={role <- @valid_roles} value={role}>{String.capitalize(to_string(role))}</option>
          </select>
          <button class="btn btn-xs btn-ghost" phx-click="deselect_all_users">Clear selection</button>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th class="w-8">
                  <input type="checkbox" class="checkbox checkbox-xs" phx-click="select_all_users" />
                </th>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th>Tracks</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @user_data.users} class={if MapSet.member?(@selected_user_ids, user.id), do: "bg-primary/10", else: ""}>
                <td>
                  <input
                    type="checkbox"
                    class="checkbox checkbox-xs"
                    checked={MapSet.member?(@selected_user_ids, user.id)}
                    phx-click="toggle_select_user"
                    phx-value-id={user.id}
                  />
                </td>
                <td>{user.email}</td>
                <td>
                  <select
                    class={"select select-bordered select-xs #{role_badge_class(user.role)}"}
                    phx-change="change_role"
                    phx-value-id={user.id}
                    name="role"
                  >
                    <option :for={role <- @valid_roles} value={role} selected={user.role == role}>
                      {String.capitalize(to_string(role))}
                    </option>
                  </select>
                </td>
                <td>
                  <span class={"badge badge-sm #{status_badge_class(user.status)}"}>
                    {user.status}
                  </span>
                </td>
                <td>{user.track_count}</td>
                <td>{Calendar.strftime(user.inserted_at, "%Y-%m-%d")}</td>
                <td class="flex gap-1">
                  <button
                    :if={user.status == :active}
                    class="btn btn-xs btn-warning"
                    phx-click="suspend_user"
                    phx-value-id={user.id}
                  >
                    Suspend
                  </button>
                  <button
                    :if={user.status == :active}
                    class="btn btn-xs btn-error"
                    phx-click="ban_user"
                    phx-value-id={user.id}
                  >
                    Ban
                  </button>
                  <button
                    :if={user.status in [:suspended, :banned]}
                    class="btn btn-xs btn-success"
                    phx-click="reactivate_user"
                    phx-value-id={user.id}
                  >
                    Reactivate
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <%!-- Pagination --%>
        <.pagination
          page={@user_data.page}
          per_page={@user_data.per_page}
          total={@user_data.total}
        />
      </div>

      <%!-- Jobs Tab --%>
      <div :if={@tab == :jobs} class="space-y-4">
        <div class="flex gap-2 mb-4">
          <button
            :for={state <- ~w(all executing available retryable discarded completed)}
            class={"btn btn-sm #{if @job_filter == state, do: "btn-primary", else: "btn-ghost"}"}
            phx-click="filter_jobs"
            phx-value-state={state}
          >
            {String.capitalize(state)}
          </button>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>ID</th>
                <th>Worker</th>
                <th>Queue</th>
                <th>State</th>
                <th>Inserted</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={job <- @jobs}>
                <td>{job.id}</td>
                <td class="font-mono text-sm">{job.worker}</td>
                <td>{job.queue}</td>
                <td>
                  <span class={"badge #{job_state_badge(job.state)}"}>
                    {job.state}
                  </span>
                </td>
                <td>{Calendar.strftime(job.inserted_at, "%Y-%m-%d %H:%M")}</td>
                <td>
                  <button
                    :if={job.state in ~w(discarded retryable)}
                    class="btn btn-xs btn-accent"
                    phx-click="retry_job"
                    phx-value-id={job.id}
                  >
                    Retry
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- System Tab --%>
      <div :if={@tab == :system} class="space-y-4">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="card bg-base-100 shadow-md p-6">
            <h2 class="text-xl font-semibold mb-4">Storage</h2>
            <p><strong>Path:</strong> {@storage[:path]}</p>
            <p><strong>Total Size:</strong> {@storage[:total_size]}</p>
          </div>

          <div class="card bg-base-100 shadow-md p-6">
            <h2 class="text-xl font-semibold mb-4">Oban Queues</h2>
            <div :for={{state, count} <- @stats.oban} class="flex justify-between py-1 border-b border-base-200 last:border-0">
              <span class="capitalize">{state}</span>
              <span class="font-mono">{count}</span>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow-md p-6">
          <h2 class="text-xl font-semibold mb-4">Role Distribution</h2>
          <div class="grid grid-cols-5 gap-4">
            <div :for={role <- @valid_roles} class="text-center">
              <div class="text-2xl font-bold">{Map.get(@stats.users_by_role, role, 0)}</div>
              <div class="text-xs text-base-content/60 capitalize">{role}</div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Analytics Tab --%>
      <div :if={@tab == :analytics} class="space-y-6">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card label="Total Users" value={@stats.user_count} />
          <.stat_card label="Total Tracks" value={@stats.track_count} />
          <.stat_card
            label="New Users (30d)"
            value={Enum.reduce(@registrations_by_day, 0, fn r, acc -> acc + r.count end)}
          />
          <.stat_card
            label="New Tracks (30d)"
            value={Enum.reduce(@tracks_by_day, 0, fn t, acc -> acc + t.count end)}
          />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="card bg-base-100 shadow-md p-6">
            <h3 class="font-semibold mb-3">User Registrations (30 days)</h3>
            <div class="flex items-end gap-1 h-32">
              <div
                :for={day <- @registrations_by_day}
                class="bg-primary/80 rounded-t min-w-[8px] flex-1 tooltip"
                data-tip={"#{day.date}: #{day.count}"}
                style={"height: #{bar_height(day.count, @registrations_by_day)}%"}
              >
              </div>
              <div :if={@registrations_by_day == []} class="text-base-content/40 text-sm w-full text-center">
                No data
              </div>
            </div>
          </div>

          <div class="card bg-base-100 shadow-md p-6">
            <h3 class="font-semibold mb-3">Track Imports (30 days)</h3>
            <div class="flex items-end gap-1 h-32">
              <div
                :for={day <- @tracks_by_day}
                class="bg-secondary/80 rounded-t min-w-[8px] flex-1 tooltip"
                data-tip={"#{day.date}: #{day.count}"}
                style={"height: #{bar_height(day.count, @tracks_by_day)}%"}
              >
              </div>
              <div :if={@tracks_by_day == []} class="text-base-content/40 text-sm w-full text-center">
                No data
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 shadow-md p-6">
          <h3 class="font-semibold mb-3">Pipeline Throughput</h3>
          <div :if={@pipeline == %{}} class="text-base-content/40 text-sm">No pipeline data</div>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div :for={{queue, stats} <- @pipeline} class="border border-base-200 rounded-lg p-4">
              <h4 class="font-medium capitalize mb-2">{queue}</h4>
              <div :for={{state, count} <- stats} class="flex justify-between text-sm py-0.5">
                <span class="capitalize text-base-content/70">{state}</span>
                <span class="font-mono">{count}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Audit Tab --%>
      <div :if={@tab == :audit} class="space-y-4">
        <div class="flex flex-wrap gap-3 items-end">
          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Search</span></label>
            <input
              type="text"
              placeholder="Search audit logs..."
              value={@audit_search}
              phx-keyup="search_audit"
              phx-key="Enter"
              phx-value-search={@audit_search}
              class="input input-bordered input-sm w-64"
              name="search"
              phx-debounce="300"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text text-xs">Action</span></label>
            <select class="select select-bordered select-sm" phx-change="filter_audit_action" name="action">
              <option value="">All Actions</option>
              <option :for={action <- ~w(role_change suspend ban reactivate bulk_role_change config_update)}
                value={action}
                selected={@audit_action_filter == action}
              >
                {String.capitalize(String.replace(action, "_", " "))}
              </option>
            </select>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Time</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Resource</th>
                <th>Changes</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={log <- @audit_logs}>
                <td class="text-sm">{Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M:%S")}</td>
                <td class="text-sm">{log.actor_email || "system"}</td>
                <td>
                  <span class={"badge badge-sm #{audit_action_badge(log.action)}"}>
                    {String.replace(log.action, "_", " ")}
                  </span>
                </td>
                <td class="text-sm font-mono">
                  {log.resource_type}:{String.slice(log.resource_id || "", 0..7)}
                </td>
                <td class="text-xs font-mono max-w-xs truncate">
                  {inspect(log.changes)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@audit_logs == []} class="text-center text-base-content/40 py-8">
          No audit logs found
        </div>
      </div>

      <%!-- LLM Tab --%>
      <div :if={@tab == :llm} class="space-y-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <.stat_card label="Total Providers" value={@llm_stats.total} />
          <.stat_card label="Enabled Providers" value={@llm_stats.enabled} />
          <.stat_card label="Healthy Providers" value={@llm_stats.healthy} />
        </div>

        <div class="card bg-base-100 shadow-md">
          <div class="card-body">
            <h2 class="card-title text-lg">Provider Health</h2>
            <p class="text-sm text-base-content/60">
              Enqueue background health checks for all your enabled LLM providers.
            </p>
            <div class="card-actions justify-end mt-4">
              <button
                class="btn btn-primary btn-sm"
                phx-click="run_health_checks"
              >
                Run Health Checks
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================
  # Components
  # ============================================================

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="stat bg-base-100 shadow-md rounded-lg">
      <div class="stat-title">{@label}</div>
      <div class="stat-value">{@value}</div>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true

  defp pagination(assigns) do
    total_pages = max(1, ceil(assigns.total / assigns.per_page))
    assigns = assign(assigns, :total_pages, total_pages)

    ~H"""
    <div :if={@total_pages > 1} class="flex justify-center gap-2 mt-4">
      <button
        :if={@page > 1}
        class="btn btn-sm"
        phx-click="users_page"
        phx-value-page={@page - 1}
      >
        Prev
      </button>
      <span class="btn btn-sm btn-ghost no-animation">
        Page {@page} of {@total_pages}
      </span>
      <button
        :if={@page < @total_pages}
        class="btn btn-sm"
        phx-click="users_page"
        phx-value-page={@page + 1}
      >
        Next
      </button>
    </div>
    """
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp tab_label(:overview), do: "Overview"
  defp tab_label(:users), do: "Users"
  defp tab_label(:jobs), do: "Jobs"
  defp tab_label(:system), do: "System"
  defp tab_label(:analytics), do: "Analytics"
  defp tab_label(:audit), do: "Audit Log"
  defp tab_label(:llm), do: "LLM"

  defp role_badge_class(:super_admin), do: "select-error"
  defp role_badge_class(:platform_admin), do: "select-warning"
  defp role_badge_class(:admin), do: "select-primary"
  defp role_badge_class(:enterprise), do: "select-accent"
  defp role_badge_class(:pro), do: "select-info"
  defp role_badge_class(_), do: ""

  defp status_badge_class(:active), do: "badge-success"
  defp status_badge_class(:suspended), do: "badge-warning"
  defp status_badge_class(:banned), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_color(:active), do: "text-success"
  defp status_color(:suspended), do: "text-warning"
  defp status_color(:banned), do: "text-error"
  defp status_color(_), do: ""

  defp job_state_badge("executing"), do: "badge-info"
  defp job_state_badge("available"), do: "badge-success"
  defp job_state_badge("discarded"), do: "badge-error"
  defp job_state_badge("retryable"), do: "badge-warning"
  defp job_state_badge("completed"), do: "badge-ghost"
  defp job_state_badge(_), do: "badge-ghost"

  defp audit_action_badge("role_change"), do: "badge-info"
  defp audit_action_badge("bulk_role_change"), do: "badge-info"
  defp audit_action_badge("suspend"), do: "badge-warning"
  defp audit_action_badge("ban"), do: "badge-error"
  defp audit_action_badge("reactivate"), do: "badge-success"
  defp audit_action_badge("config_update"), do: "badge-accent"
  defp audit_action_badge(_), do: "badge-ghost"

  defp bar_height(_count, []), do: 0

  defp bar_height(count, data) do
    max_count = Enum.max_by(data, & &1.count).count

    if max_count == 0,
      do: 0,
      else: round(count / max_count * 100)
  end
end
