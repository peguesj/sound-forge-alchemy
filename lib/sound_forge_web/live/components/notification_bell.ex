defmodule SoundForgeWeb.Live.Components.NotificationBell do
  @moduledoc """
  LiveComponent rendering a notification bell icon with an unread count badge
  and a dropdown panel of recent pipeline events.

  ## Required assigns

    - `:user_id` - integer or binary user ID for fetching notifications

  ## Usage in a parent LiveView template

      <.live_component
        module={SoundForgeWeb.Live.Components.NotificationBell}
        id="notification-bell"
        user_id={@current_user_id}
      />

  The parent LiveView must forward PubSub messages. In `mount/3`:

      if connected?(socket) do
        SoundForge.Notifications.subscribe(user_id)
      end

  And in `handle_info/2`:

      def handle_info({:new_notification, _notification} = msg, socket) do
        send_update(SoundForgeWeb.Live.Components.NotificationBell,
          id: "notification-bell",
          refresh: true
        )
        {:noreply, socket}
      end
  """
  use SoundForgeWeb, :live_component

  alias SoundForge.Notifications

  @notification_limit 20

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:notifications, [])
     |> assign(:unread_count, 0)}
  end

  @impl true
  def update(%{refresh: true} = _assigns, socket) do
    user_id = socket.assigns[:user_id]
    {:ok, load_notifications(socket, user_id)}
  end

  def update(assigns, socket) do
    user_id = assigns[:user_id] || socket.assigns[:user_id]

    {:ok,
     socket
     |> assign(assigns)
     |> load_notifications(user_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="relative">
      <!-- Bell Button -->
      <button
        type="button"
        phx-click="toggle_bell"
        phx-target={@myself}
        aria-label={"Notifications, #{@unread_count} unread"}
        aria-expanded={to_string(@open)}
        aria-haspopup="true"
        class="relative p-2 text-gray-400 hover:text-white transition-colors rounded-lg hover:bg-gray-800"
      >
        <svg
          class="w-6 h-6"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0"
          />
        </svg>
        <!-- Unread Badge -->
        <span
          :if={@unread_count > 0}
          class="absolute -top-0.5 -right-0.5 flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-bold text-white bg-red-500 rounded-full"
        >
          {badge_text(@unread_count)}
        </span>
      </button>
      
    <!-- Dropdown Panel -->
      <div
        :if={@open}
        id={"#{@id}-dropdown"}
        phx-click-away="close_bell"
        phx-target={@myself}
        class="absolute right-0 top-full mt-2 w-80 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 overflow-hidden"
        role="menu"
        aria-label="Notification panel"
      >
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-gray-700">
          <h3 class="text-sm font-semibold text-white">Notifications</h3>
          <span :if={@unread_count > 0} class="text-xs text-gray-500">
            {badge_text(@unread_count)} unread
          </span>
        </div>
        
    <!-- Notification List -->
        <div class="max-h-96 overflow-y-auto">
          <div
            :if={length(@notifications) == 0}
            class="px-4 py-8 text-center text-sm text-gray-500"
          >
            No notifications yet
          </div>

          <div
            :for={notification <- @notifications}
            class={[
              "flex items-start gap-3 px-4 py-3 border-b border-gray-700/50 last:border-0",
              if(!notification.read, do: "bg-gray-750/50", else: "")
            ]}
          >
            <!-- Type Icon -->
            <div class={["shrink-0 mt-0.5", notification_icon_class(notification.type)]}>
              {notification_icon(notification.type)}
            </div>
            <!-- Content -->
            <div class="flex-1 min-w-0">
              <p :if={notification.title != ""} class="text-sm font-medium text-white truncate">
                {notification.title}
              </p>
              <p class="text-xs text-gray-400 line-clamp-2">{notification.message}</p>
              <p class="text-[10px] text-gray-600 mt-1">
                {relative_time(notification.inserted_at)}
              </p>
            </div>
            <!-- Unread Indicator -->
            <div
              :if={!notification.read}
              class="shrink-0 mt-1.5 w-2 h-2 rounded-full bg-purple-400"
              aria-label="Unread"
            >
            </div>
          </div>
        </div>
        
    <!-- Footer -->
        <div :if={@unread_count > 0} class="border-t border-gray-700 px-4 py-2.5">
          <button
            type="button"
            phx-click="mark_all_read"
            phx-target={@myself}
            class="w-full text-center text-xs text-purple-400 hover:text-purple-300 transition-colors font-medium"
          >
            Mark all as read
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_bell", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  @impl true
  def handle_event("close_bell", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    user_id = socket.assigns.user_id

    if user_id do
      Notifications.mark_read(user_id)
    end

    {:noreply, load_notifications(socket, user_id)}
  end

  # -- Private helpers --

  defp load_notifications(socket, nil) do
    socket
    |> assign(:notifications, [])
    |> assign(:unread_count, 0)
  end

  defp load_notifications(socket, user_id) do
    notifications = Notifications.list(user_id, @notification_limit)
    unread = Notifications.unread_count(user_id)

    socket
    |> assign(:notifications, notifications)
    |> assign(:unread_count, unread)
  end

  defp badge_text(count) when count > 99, do: "99+"
  defp badge_text(count), do: to_string(count)

  defp notification_icon_class(:info), do: "text-purple-400"
  defp notification_icon_class(:success), do: "text-green-400"
  defp notification_icon_class(:warning), do: "text-amber-400"
  defp notification_icon_class(:error), do: "text-red-400"
  defp notification_icon_class(_), do: "text-gray-400"

  defp notification_icon(:info) do
    assigns = %{}

    ~H"""
    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp notification_icon(:success) do
    assigns = %{}

    ~H"""
    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp notification_icon(:warning) do
    assigns = %{}

    ~H"""
    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp notification_icon(:error) do
    assigns = %{}

    ~H"""
    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp notification_icon(_) do
    assigns = %{}

    ~H"""
    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
