defmodule SoundForgeWeb.AdminLive do
  @moduledoc """
  Admin dashboard LiveView with overview, users, jobs, and system tabs.
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Admin

  @admin_tabs ~w(overview users jobs system)a

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> assign(:admin_tabs, @admin_tabs)
      |> assign(:tab, :overview)
      |> assign(:stats, Admin.system_stats())
      |> assign(:users, [])
      |> assign(:jobs, [])
      |> assign(:storage, %{})
      |> assign(:job_filter, "all")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        tab when tab in ~w(overview users jobs system) -> String.to_existing_atom(tab)
        _ -> :overview
      end

    socket = assign(socket, :tab, tab) |> load_tab_data()
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?tab=#{tab}")}
  end

  def handle_event("promote", %{"id" => id}, socket) do
    {:ok, _} = Admin.update_user_role(String.to_integer(id), :admin)
    {:noreply, assign(socket, :users, Admin.list_users())}
  end

  def handle_event("demote", %{"id" => id}, socket) do
    {:ok, _} = Admin.update_user_role(String.to_integer(id), :user)
    {:noreply, assign(socket, :users, Admin.list_users())}
  end

  def handle_event("filter_jobs", %{"state" => state}, socket) do
    jobs = Admin.all_jobs(state: state)
    {:noreply, assign(socket, jobs: jobs, job_filter: state)}
  end

  def handle_event("retry_job", %{"id" => id}, socket) do
    Oban.retry_job(String.to_integer(id))
    jobs = Admin.all_jobs(state: socket.assigns.job_filter)
    {:noreply, assign(socket, :jobs, jobs)}
  end

  defp load_tab_data(%{assigns: %{tab: :overview}} = socket) do
    assign(socket, :stats, Admin.system_stats())
  end

  defp load_tab_data(%{assigns: %{tab: :users}} = socket) do
    assign(socket, :users, Admin.list_users())
  end

  defp load_tab_data(%{assigns: %{tab: :jobs}} = socket) do
    assign(socket, :jobs, Admin.all_jobs(state: socket.assigns.job_filter))
  end

  defp load_tab_data(%{assigns: %{tab: :system}} = socket) do
    assign(socket, :storage, Admin.storage_stats())
  end

  defp load_tab_data(socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-6">
      <h1 class="text-3xl font-bold mb-6">Admin Dashboard</h1>

      <div class="tabs tabs-boxed mb-6">
        <button
          :for={tab <- @admin_tabs}
          class={"tab #{if @tab == tab, do: "tab-active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {tab |> to_string() |> String.capitalize()}
        </button>
      </div>

      <div :if={@tab == :overview} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Users" value={@stats.user_count} />
        <.stat_card label="Tracks" value={@stats.track_count} />
        <.stat_card label="Active Jobs" value={Map.get(@stats.oban, "executing", 0)} />
        <.stat_card label="Failed Jobs" value={Map.get(@stats.oban, "discarded", 0)} />
      </div>

      <div :if={@tab == :users}>
        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Tracks</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @users}>
                <td>{user.email}</td>
                <td>
                  <span class={"badge #{if user.role == :admin, do: "badge-primary", else: "badge-ghost"}"}>
                    {user.role}
                  </span>
                </td>
                <td>{user.track_count}</td>
                <td>{Calendar.strftime(user.inserted_at, "%Y-%m-%d")}</td>
                <td>
                  <button
                    :if={user.role == :user}
                    class="btn btn-xs btn-primary"
                    phx-click="promote"
                    phx-value-id={user.id}
                  >
                    Promote
                  </button>
                  <button
                    :if={user.role == :admin}
                    class="btn btn-xs btn-warning"
                    phx-click="demote"
                    phx-value-id={user.id}
                  >
                    Demote
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@tab == :jobs}>
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

      <div :if={@tab == :system} class="space-y-4">
        <div class="card bg-base-100 shadow-md p-6">
          <h2 class="text-xl font-semibold mb-4">Storage</h2>
          <p><strong>Path:</strong> {@storage[:path]}</p>
          <p><strong>Total Size:</strong> {@storage[:total_size]}</p>
        </div>

        <div class="card bg-base-100 shadow-md p-6">
          <h2 class="text-xl font-semibold mb-4">Oban Queues</h2>
          <div :for={{state, count} <- @stats.oban} class="flex justify-between py-1">
            <span class="capitalize">{state}</span>
            <span class="font-mono">{count}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

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

  defp job_state_badge("executing"), do: "badge-info"
  defp job_state_badge("available"), do: "badge-success"
  defp job_state_badge("discarded"), do: "badge-error"
  defp job_state_badge("retryable"), do: "badge-warning"
  defp job_state_badge("completed"), do: "badge-ghost"
  defp job_state_badge(_), do: "badge-ghost"
end
