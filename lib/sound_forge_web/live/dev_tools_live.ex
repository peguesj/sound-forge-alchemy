defmodule SoundForgeWeb.DevToolsLive do
  @moduledoc """
  Developer tools panel for inspecting system state.
  Accessible to admin and super_admin users only.

  Displays:
  - Seed users and their configuration
  - Safe environment variable summary (keys present/absent, no values)
  - System runtime info (OTP, Elixir, Phoenix versions, node, memory)
  - Application config summary
  """
  use SoundForgeWeb, :live_view

  import Ecto.Query, warn: false

  alias SoundForge.Repo
  alias SoundForge.Accounts.User

  @tabs ~w(seed_users env_vars system_info app_config)a

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Dev Tools")
      |> assign(:active_tab, :seed_users)
      |> assign(:tabs, @tabs)
      |> assign(:seed_users, list_seed_users())
      |> assign(:env_vars, safe_env_vars())
      |> assign(:system_info, system_info())
      |> assign(:app_config, app_config_summary())

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) do
    if String.to_existing_atom(tab) in @tabs do
      {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
    else
      {:noreply, socket}
    end
  rescue
    ArgumentError -> {:noreply, socket}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/dev-tools?tab=#{tab}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto p-6">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-base-content">Dev Tools</h1>
        <p class="text-base-content/60 text-sm mt-1">System inspection panel — read-only</p>
      </div>

      <%!-- Tab navigation --%>
      <div class="tabs tabs-bordered mb-6">
        <button
          :for={tab <- @tabs}
          class={["tab", @active_tab == tab && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <%!-- Seed Users tab --%>
      <div :if={@active_tab == :seed_users}>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-base">Seed Users</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Demo accounts from <code class="bg-base-300 px-1 rounded">priv/repo/seeds.exs</code>.
              Asterisk (*) indicates user exists in the database.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>In DB?</th>
                    <th>Confirmed?</th>
                    <th>lalal.ai Key?</th>
                    <th>Settings?</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={u <- @seed_users}>
                    <td class="font-mono text-sm">{u.email}</td>
                    <td>
                      <span class={["badge badge-sm", role_badge_class(u.role)]}>
                        {u.role || "—"}
                      </span>
                    </td>
                    <td>
                      <span class={["badge badge-sm", u.exists? && "badge-success" || "badge-ghost"]}>
                        {u.exists? && "yes" || "no"}
                      </span>
                    </td>
                    <td>
                      {if u.confirmed_at, do: Calendar.strftime(u.confirmed_at, "%Y-%m-%d"), else: "—"}
                    </td>
                    <td>
                      <span class={["badge badge-sm", u.has_lalalai_key? && "badge-success" || "badge-ghost"]}>
                        {u.has_lalalai_key? && "yes" || "no"}
                      </span>
                    </td>
                    <td>
                      <span class={["badge badge-sm", u.has_settings? && "badge-success" || "badge-ghost"]}>
                        {u.has_settings? && "yes" || "no"}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <%!-- Env Vars tab --%>
      <div :if={@active_tab == :env_vars}>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-base">Environment Variables</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Shows whether each key is set. Values are never displayed.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Variable</th>
                    <th>Category</th>
                    <th>Status</th>
                    <th>Notes</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={ev <- @env_vars}>
                    <td class="font-mono text-sm">{ev.name}</td>
                    <td class="text-sm text-base-content/60">{ev.category}</td>
                    <td>
                      <span class={["badge badge-sm", ev.set? && "badge-success" || "badge-warning"]}>
                        {ev.set? && "set" || "not set"}
                      </span>
                    </td>
                    <td class="text-sm text-base-content/60">{ev.notes}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <%!-- System Info tab --%>
      <div :if={@active_tab == :system_info}>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-base">System Info</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
              <div :for={item <- @system_info} class="flex justify-between border-b border-base-300 pb-2">
                <span class="text-sm font-medium text-base-content/70">{item.label}</span>
                <span class="text-sm font-mono">{item.value}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- App Config tab --%>
      <div :if={@active_tab == :app_config}>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-base">Application Config Summary</h2>
            <p class="text-sm text-base-content/60 mb-4">
              Key runtime config values. Sensitive values are masked.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Key</th>
                    <th>Value</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={item <- @app_config}>
                    <td class="font-mono text-sm">{item.key}</td>
                    <td class="font-mono text-sm">{item.value}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Data loaders
  # ---------------------------------------------------------------------------

  @seed_emails ~w(
    dev@soundforge.local
    demo-free@soundforge.local
    demo-pro@soundforge.local
    demo-enterprise@soundforge.local
    admin@soundforge.local
    super@soundforge.local
  )

  defp list_seed_users do
    existing =
      Repo.all(
        from u in User,
          where: u.email in ^@seed_emails,
          preload: [:settings]
      )

    existing_by_email = Map.new(existing, &{&1.email, &1})

    Enum.map(@seed_emails, fn email ->
      case Map.get(existing_by_email, email) do
        nil ->
          %{
            email: email,
            role: nil,
            exists?: false,
            confirmed_at: nil,
            has_lalalai_key?: false,
            has_settings?: false
          }

        user ->
          lalalai_set? =
            case user.settings do
              %{lalalai_api_key: key} when is_binary(key) and byte_size(key) > 0 -> true
              _ -> false
            end

          %{
            email: user.email,
            role: user.role,
            exists?: true,
            confirmed_at: user.confirmed_at,
            has_lalalai_key?: lalalai_set?,
            has_settings?: not is_nil(user.settings)
          }
      end
    end)
  end

  @watched_env_vars [
    %{
      name: "SPOTIFY_CLIENT_ID",
      category: "Spotify",
      notes: "Required for metadata fetching"
    },
    %{
      name: "SPOTIFY_CLIENT_SECRET",
      category: "Spotify",
      notes: "Required for metadata fetching"
    },
    %{
      name: "LALALAI_API_KEY",
      category: "lalal.ai",
      notes: "Global fallback API key"
    },
    %{
      name: "SYSTEM_LALALAI_ACTIVATION_KEY",
      category: "lalal.ai",
      notes: "Auto-granted to pro/enterprise/admin in seeds"
    },
    %{
      name: "DATABASE_URL",
      category: "Database",
      notes: "Required in production"
    },
    %{
      name: "SECRET_KEY_BASE",
      category: "Security",
      notes: "Required in production"
    },
    %{
      name: "PHX_HOST",
      category: "Phoenix",
      notes: "Public hostname for production"
    },
    %{
      name: "PHX_SERVER",
      category: "Phoenix",
      notes: "Enable server in release mode"
    },
    %{
      name: "SPOTIPY_CLIENT_ID",
      category: "Python / spotdl",
      notes: "Alias of SPOTIFY_CLIENT_ID for spotdl CLI"
    },
    %{
      name: "SPOTIPY_CLIENT_SECRET",
      category: "Python / spotdl",
      notes: "Alias of SPOTIFY_CLIENT_SECRET for spotdl CLI"
    }
  ]

  defp safe_env_vars do
    Enum.map(@watched_env_vars, fn ev ->
      Map.put(ev, :set?, not is_nil(System.get_env(ev.name)))
    end)
  end

  defp system_info do
    mem = :erlang.memory()
    total_mem = Keyword.get(mem, :total, 0)
    process_mem = Keyword.get(mem, :processes, 0)

    [
      %{label: "Elixir version", value: System.version()},
      %{label: "OTP release", value: System.otp_release()},
      %{label: "ERTS version", value: :erlang.system_info(:version) |> to_string()},
      %{label: "Node", value: inspect(node())},
      %{label: "Config env", value: inspect(Application.get_env(:sound_forge, :env, :dev))},
      %{label: "Schedulers online", value: inspect(:erlang.system_info(:schedulers_online))},
      %{
        label: "Process count",
        value: inspect(length(Process.list()))
      },
      %{
        label: "Total VM memory (MB)",
        value: format_bytes(total_mem)
      },
      %{
        label: "Process memory (MB)",
        value: format_bytes(process_mem)
      },
      %{label: "System time (UTC)", value: DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")}
    ]
  end

  defp app_config_summary do
    spotify_id = Application.get_env(:sound_forge, :spotify, []) |> Keyword.get(:client_id)
    lalalai_key = Application.get_env(:sound_forge, :lalalai_api_key)
    system_key = Application.get_env(:sound_forge, :system_lalalai_key)

    [
      %{
        key: ":sound_forge, :spotify :client_id",
        value: mask_value(spotify_id)
      },
      %{
        key: ":sound_forge, :spotify :client_secret",
        value: present_or_absent(Application.get_env(:sound_forge, :spotify, []) |> Keyword.get(:client_secret))
      },
      %{
        key: ":sound_forge, :lalalai_api_key",
        value: mask_value(lalalai_key)
      },
      %{
        key: ":sound_forge, :system_lalalai_key",
        value: mask_value(system_key)
      },
      %{
        key: ":sound_forge, :default_demucs_model",
        value: inspect(Application.get_env(:sound_forge, :default_demucs_model, "htdemucs"))
      },
      %{
        key: ":sound_forge, :downloads_dir",
        value: inspect(Application.get_env(:sound_forge, :downloads_dir, "priv/uploads/downloads"))
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tab_label(:seed_users), do: "Seed Users"
  defp tab_label(:env_vars), do: "Env Vars"
  defp tab_label(:system_info), do: "System Info"
  defp tab_label(:app_config), do: "App Config"

  defp role_badge_class(:super_admin), do: "badge-error"
  defp role_badge_class(:admin), do: "badge-warning"
  defp role_badge_class(:enterprise), do: "badge-primary"
  defp role_badge_class(:pro), do: "badge-secondary"
  defp role_badge_class(:user), do: "badge-ghost"
  defp role_badge_class(_), do: "badge-ghost"

  defp mask_value(nil), do: "(not set)"
  defp mask_value(""), do: "(empty)"

  defp mask_value(val) when is_binary(val) do
    len = byte_size(val)

    if len <= 8 do
      String.duplicate("*", len)
    else
      String.slice(val, 0, 4) <> String.duplicate("*", min(len - 4, 20)) <> "…"
    end
  end

  defp mask_value(val), do: inspect(val)

  defp present_or_absent(nil), do: "(not set)"
  defp present_or_absent(""), do: "(empty)"
  defp present_or_absent(_), do: "(set)"

  defp format_bytes(nil), do: "n/a"

  defp format_bytes(bytes) when is_integer(bytes) do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb} MB"
  end
end
