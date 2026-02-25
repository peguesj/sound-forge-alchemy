defmodule SoundForgeWeb.PrototypeLive do
  @moduledoc """
  Developer sandbox and UAT runner. Accessible in :dev environment only
  to users with admin, super_admin, or platform_admin roles.

  Tabs:
    - Components   : daisyUI component showcase
    - DevTools     : Oban stats, LLM provider health, assigns inspector
    - UAT          : Scenario runner and fixture loader
    - LLM Sandbox  : Free-form chat piped through Agents.Orchestrator
  """
  use SoundForgeWeb, :live_view

  alias SoundForge.Admin
  alias SoundForge.Agents.{Context, Orchestrator}

  @prototype_tabs ~w(components devtools uat llm_sandbox)a

  # ============================================================
  # Mount / Params
  # ============================================================

  @impl true
  def mount(_params, session, socket) do
    socket =
      if is_nil(socket.assigns[:current_scope]) do
        scope = load_scope_from_session(session)
        assign(socket, :current_scope, scope)
      else
        socket
      end

    case check_prototype_access(socket) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:page_title, "Prototype Sandbox")
          |> assign(:tab, :components)
          |> assign(:prototype_tabs, @prototype_tabs)
          # DevTools tab assigns
          |> assign(:oban_stats, %{})
          |> assign(:llm_stats, %{total: 0, enabled: 0, healthy: 0})
          |> assign(:assigns_keys, [])
          # UAT tab assigns
          |> assign(:uat_scenarios, uat_scenarios())
          |> assign(:uat_results, %{})
          |> assign(:uat_loading, MapSet.new())
          # LLM Sandbox assigns
          |> assign(:llm_input, "")
          |> assign(:llm_loading, false)
          |> assign(:llm_messages, [])

        {:ok, socket}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "Prototype sandbox is only accessible in the dev environment to admin users.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        t when t in ~w(components devtools uat llm_sandbox) ->
          String.to_existing_atom(t)

        _ ->
          :components
      end

    socket =
      socket
      |> assign(:tab, tab)
      |> load_tab_data(tab)

    {:noreply, socket}
  end

  # ============================================================
  # Events
  # ============================================================

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/prototype?tab=#{tab}")}
  end

  # UAT: run a named scenario
  def handle_event("run_scenario", %{"scenario" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id
    loading = MapSet.put(socket.assigns.uat_loading, name)
    socket = assign(socket, :uat_loading, loading)

    # Run scenario async so we don't block the LV process
    pid = self()

    Task.start(fn ->
      result = SoundForge.UAT.run_scenario(name, user_id)
      send(pid, {:uat_result, name, result})
    end)

    {:noreply, socket}
  end

  # UAT: clear all UAT fixtures
  def handle_event("clear_uat_data", _params, socket) do
    result =
      try do
        SoundForge.UAT.clear_test_data()
        {:ok, "Test data cleared."}
      rescue
        e -> {:error, Exception.message(e)}
      end

    msg = case result do
      {:ok, m} -> m
      {:error, m} -> "Error: #{m}"
    end

    {:noreply, put_flash(socket, :info, msg)}
  end

  # LLM Sandbox: update input
  def handle_event("llm_input_change", %{"value" => value}, socket) do
    {:noreply, assign(socket, :llm_input, value)}
  end

  # LLM Sandbox: send to orchestrator
  def handle_event("llm_send", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      user_msg = %{role: :user, content: message, id: System.unique_integer([:positive])}
      messages = socket.assigns.llm_messages ++ [user_msg]
      user_id = socket.assigns.current_scope.user.id
      pid = self()

      Task.start(fn ->
        ctx = Context.new(message, user_id: user_id)
        result = Orchestrator.run(ctx)
        send(pid, {:llm_result, result})
      end)

      {:noreply,
       socket
       |> assign(:llm_messages, messages)
       |> assign(:llm_input, "")
       |> assign(:llm_loading, true)}
    end
  end

  def handle_event("llm_clear", _params, socket) do
    {:noreply, assign(socket, :llm_messages, [])}
  end

  # ============================================================
  # Info handlers (async results)
  # ============================================================

  @impl true
  def handle_info({:uat_result, name, result}, socket) do
    loading = MapSet.delete(socket.assigns.uat_loading, name)
    results = Map.put(socket.assigns.uat_results, name, result)

    {:noreply,
     socket
     |> assign(:uat_loading, loading)
     |> assign(:uat_results, results)}
  end

  def handle_info({:llm_result, result}, socket) do
    msg =
      case result do
        {:ok, r} ->
          %{role: :agent, content: r.content || "(no response)", id: System.unique_integer([:positive])}

        {:error, reason} ->
          %{role: :error, content: "Error: #{inspect(reason)}", id: System.unique_integer([:positive])}
      end

    messages = socket.assigns.llm_messages ++ [msg]

    {:noreply,
     socket
     |> assign(:llm_messages, messages)
     |> assign(:llm_loading, false)}
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
          <h1 class="text-3xl font-bold">Prototype Sandbox</h1>
          <p class="text-sm text-base-content/60 mt-1">Dev-only — not visible in production</p>
        </div>
        <span class="badge badge-accent badge-lg">DEV</span>
      </div>

      <%!-- Tab bar --%>
      <div class="tabs tabs-boxed mb-6">
        <button
          :for={tab <- @prototype_tabs}
          class={"tab #{if @tab == tab, do: "tab-active", else: ""}"}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <%!-- Components tab --%>
      <div :if={@tab == :components}>
        <.component_showcase />
      </div>

      <%!-- DevTools tab --%>
      <div :if={@tab == :devtools} class="space-y-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <.stat_card label="Oban Executing" value={Map.get(@oban_stats, "executing", 0)} />
          <.stat_card label="Oban Available" value={Map.get(@oban_stats, "available", 0)} />
          <.stat_card label="Oban Failed" value={Map.get(@oban_stats, "discarded", 0)} />
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <.stat_card label="LLM Providers" value={@llm_stats.total} />
          <.stat_card label="LLM Enabled" value={@llm_stats.enabled} />
          <.stat_card label="LLM Healthy" value={@llm_stats.healthy} />
        </div>

        <div class="card bg-base-100 shadow-md p-6">
          <h3 class="font-semibold mb-3">Assigns Inspector</h3>
          <div class="flex flex-wrap gap-2">
            <span :for={key <- @assigns_keys} class="badge badge-outline font-mono text-xs">
              {key}
            </span>
          </div>
        </div>

        <div class="card bg-base-100 shadow-md p-6">
          <h3 class="font-semibold mb-3">Quick Links</h3>
          <div class="flex gap-3">
            <a href="/admin" class="btn btn-sm btn-primary">Admin Dashboard</a>
            <a href="/admin/dev-tools" class="btn btn-sm btn-secondary">Dev Tools</a>
            <a href="/platform/library" class="btn btn-sm btn-warning">Platform Library</a>
          </div>
        </div>
      </div>

      <%!-- UAT tab --%>
      <div :if={@tab == :uat} class="space-y-4">
        <div class="flex justify-between items-center">
          <h2 class="text-xl font-semibold">UAT Scenarios</h2>
          <button class="btn btn-sm btn-error btn-outline" phx-click="clear_uat_data">
            Clear All UAT Data
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div :for={scenario <- @uat_scenarios} class="card bg-base-100 shadow-md">
            <div class="card-body">
              <h3 class="card-title text-base">{scenario.label}</h3>
              <p class="text-sm text-base-content/60">{scenario.description}</p>

              <div :if={Map.has_key?(@uat_results, scenario.name)} class="mt-2">
                <.uat_result result={Map.get(@uat_results, scenario.name)} />
              </div>

              <div class="card-actions justify-end mt-3">
                <button
                  class="btn btn-sm btn-primary"
                  phx-click="run_scenario"
                  phx-value-scenario={scenario.name}
                  disabled={MapSet.member?(@uat_loading, scenario.name)}
                >
                  {if MapSet.member?(@uat_loading, scenario.name), do: "Running...", else: "Run"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- LLM Sandbox tab --%>
      <div :if={@tab == :llm_sandbox} class="max-w-2xl">
        <div class="card bg-base-100 shadow-md">
          <div class="card-body">
            <div class="flex justify-between items-center mb-4">
              <h2 class="card-title">LLM Orchestrator Sandbox</h2>
              <button :if={@llm_messages != []} class="btn btn-xs btn-ghost" phx-click="llm_clear">
                Clear
              </button>
            </div>

            <div class="space-y-3 min-h-[200px] max-h-[400px] overflow-y-auto mb-4">
              <div :if={@llm_messages == []} class="text-center text-base-content/40 py-8">
                Send a message to the Orchestrator
              </div>

              <div :for={msg <- @llm_messages} class={"flex #{if msg.role == :user, do: "justify-end", else: "justify-start"}"}>
                <div class={"max-w-md rounded-xl px-3 py-2 text-sm #{msg_class(msg.role)}"}>
                  <p class="whitespace-pre-wrap">{msg.content}</p>
                </div>
              </div>

              <div :if={@llm_loading} class="flex justify-start">
                <div class="bg-base-200 rounded-xl px-3 py-2 text-sm text-base-content/60">
                  Thinking...
                </div>
              </div>
            </div>

            <form phx-submit="llm_send" class="flex gap-2">
              <input
                type="text"
                name="message"
                value={@llm_input}
                phx-change="llm_input_change"
                phx-target="#prototype-llm-input"
                placeholder="Ask the orchestrator..."
                autocomplete="off"
                disabled={@llm_loading}
                class="input input-bordered flex-1"
              />
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@llm_loading || String.trim(@llm_input) == ""}
              >
                Send
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================
  # Sub-components
  # ============================================================

  defp component_showcase(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Buttons --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Buttons</h3>
        <div class="flex flex-wrap gap-3">
          <button class="btn">Default</button>
          <button class="btn btn-primary">Primary</button>
          <button class="btn btn-secondary">Secondary</button>
          <button class="btn btn-accent">Accent</button>
          <button class="btn btn-ghost">Ghost</button>
          <button class="btn btn-outline">Outline</button>
          <button class="btn btn-error">Error</button>
          <button class="btn btn-warning">Warning</button>
          <button class="btn btn-success">Success</button>
          <button class="btn btn-info">Info</button>
          <button class="btn btn-xs">XS</button>
          <button class="btn btn-sm">SM</button>
          <button class="btn btn-lg">LG</button>
          <button class="btn btn-loading">Loading</button>
          <button class="btn" disabled>Disabled</button>
        </div>
      </div>

      <%!-- Badges --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Badges</h3>
        <div class="flex flex-wrap gap-3">
          <span class="badge">Default</span>
          <span class="badge badge-primary">Primary</span>
          <span class="badge badge-secondary">Secondary</span>
          <span class="badge badge-accent">Accent</span>
          <span class="badge badge-ghost">Ghost</span>
          <span class="badge badge-outline">Outline</span>
          <span class="badge badge-error">Error</span>
          <span class="badge badge-warning">Warning</span>
          <span class="badge badge-success">Success</span>
          <span class="badge badge-info">Info</span>
          <span class="badge badge-xs">XS</span>
          <span class="badge badge-sm">SM</span>
          <span class="badge badge-lg">LG</span>
        </div>
      </div>

      <%!-- Cards --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Cards</h3>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title">Card Title</h2>
              <p class="text-sm text-base-content/60">Card content goes here.</p>
              <div class="card-actions justify-end">
                <button class="btn btn-primary btn-sm">Action</button>
              </div>
            </div>
          </div>
          <div class="card bg-primary text-primary-content shadow">
            <div class="card-body">
              <h2 class="card-title">Primary Card</h2>
              <p class="text-sm">Colored card example.</p>
            </div>
          </div>
          <div class="card border border-base-300 shadow">
            <div class="card-body">
              <h2 class="card-title">Bordered Card</h2>
              <p class="text-sm text-base-content/60">With border styling.</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Stats --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Stats</h3>
        <div class="stats stats-vertical md:stats-horizontal shadow w-full">
          <div class="stat">
            <div class="stat-title">Downloads</div>
            <div class="stat-value">31K</div>
            <div class="stat-desc">Jan 1st - Feb 1st</div>
          </div>
          <div class="stat">
            <div class="stat-title">New Users</div>
            <div class="stat-value text-secondary">4,200</div>
            <div class="stat-desc text-secondary">21% more than last month</div>
          </div>
          <div class="stat">
            <div class="stat-title">New Tracks</div>
            <div class="stat-value">1,200</div>
            <div class="stat-desc">90 from admins</div>
          </div>
        </div>
      </div>

      <%!-- Alerts --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Alerts</h3>
        <div class="space-y-3">
          <div class="alert alert-info"><span>Info alert message</span></div>
          <div class="alert alert-success"><span>Success alert message</span></div>
          <div class="alert alert-warning"><span>Warning alert message</span></div>
          <div class="alert alert-error"><span>Error alert message</span></div>
        </div>
      </div>

      <%!-- Form Inputs --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Form Inputs</h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Text input</span></label>
            <input type="text" placeholder="Type here" class="input input-bordered" />
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Select</span></label>
            <select class="select select-bordered">
              <option>Option 1</option>
              <option>Option 2</option>
            </select>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Textarea</span></label>
            <textarea class="textarea textarea-bordered" placeholder="Enter text..."></textarea>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Toggle</span></label>
            <input type="checkbox" class="toggle toggle-primary" />
            <label class="label"><span class="label-text">Checkbox</span></label>
            <input type="checkbox" class="checkbox checkbox-primary" />
          </div>
        </div>
      </div>

      <%!-- Table --%>
      <div class="card bg-base-100 shadow-md p-6">
        <h3 class="font-semibold text-lg mb-4">Table</h3>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Name</th>
                <th>Role</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Alice Smith</td>
                <td><span class="badge badge-primary">Admin</span></td>
                <td><span class="badge badge-success">Active</span></td>
                <td><button class="btn btn-xs">Edit</button></td>
              </tr>
              <tr>
                <td>Bob Jones</td>
                <td><span class="badge badge-secondary">Pro</span></td>
                <td><span class="badge badge-warning">Suspended</span></td>
                <td><button class="btn btn-xs">Edit</button></td>
              </tr>
              <tr>
                <td>Carol Lee</td>
                <td><span class="badge badge-ghost">User</span></td>
                <td><span class="badge badge-success">Active</span></td>
                <td><button class="btn btn-xs">Edit</button></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr :result, :any, required: true

  defp uat_result(%{result: {:ok, track}} = assigns) do
    assigns = assign(assigns, :track, track)

    ~H"""
    <div class="alert alert-success text-sm py-2">
      <span>Created track: {@track.title} (ID: {String.slice(to_string(@track.id), 0, 8)}...)</span>
    </div>
    """
  end

  defp uat_result(%{result: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <div class="alert alert-error text-sm py-2">
      <span>Error: {@reason}</span>
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

  # ============================================================
  # Data loading
  # ============================================================

  defp load_tab_data(socket, :devtools) do
    stats = Admin.system_stats()
    assigns_keys = socket.assigns |> Map.keys() |> Enum.sort() |> Enum.map(&to_string/1)

    socket
    |> assign(:oban_stats, stats.oban)
    |> assign(:llm_stats, Admin.llm_stats())
    |> assign(:assigns_keys, assigns_keys)
  end

  defp load_tab_data(socket, _tab), do: socket

  # ============================================================
  # Access guard
  # ============================================================

  defp check_prototype_access(socket) do
    role = socket.assigns[:current_scope] && socket.assigns.current_scope.role

    if Mix.env() == :dev and role in [:admin, :super_admin, :platform_admin] do
      {:ok, socket}
    else
      {:error, :unauthorized}
    end
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp tab_label(:components), do: "Components"
  defp tab_label(:devtools), do: "DevTools"
  defp tab_label(:uat), do: "UAT"
  defp tab_label(:llm_sandbox), do: "LLM Sandbox"

  defp msg_class(:user), do: "bg-primary text-primary-content"
  defp msg_class(:agent), do: "bg-base-200 text-base-content"
  defp msg_class(:error), do: "bg-error/20 text-error"

  defp uat_scenarios do
    [
      %{
        name: "import_spotify_track",
        label: "Import Spotify Track",
        description: "Seeds a UAT test track in :pending state for the current user."
      },
      %{
        name: "run_stem_separation",
        label: "Run Stem Separation",
        description: "Seeds a UAT track and enqueues a StemSeparationWorker job."
      }
    ]
  end

  defp load_scope_from_session(session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- SoundForge.Accounts.get_user_by_session_token(token) do
      SoundForge.Accounts.Scope.for_user(user)
    else
      _ -> nil
    end
  end
end
