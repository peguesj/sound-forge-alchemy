defmodule SoundForgeWeb.Live.Components.ToastStack do
  @moduledoc """
  LiveComponent for stacking notification toasts in the bottom-right corner.

  Toasts are pushed from parent LiveViews via `send_update/2`:

      send_update(SoundForgeWeb.Live.Components.ToastStack,
        id: "toast-stack",
        toast: %{type: :info, title: "Title", message: "Message"}
      )

  Types: :info (purple), :success (green), :warning (amber), :error (red).
  Maximum 5 visible toasts; oldest dismissed first when exceeded.
  Auto-dismiss after 5 seconds via a JS-driven phx-mounted hook.
  """
  use SoundForgeWeb, :live_component

  @max_toasts 5

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :toasts, [])}
  end

  @impl true
  def update(%{toast: toast} = assigns, socket) do
    socket = assign_defaults(socket, assigns)

    id = Ecto.UUID.generate()
    inserted_at = DateTime.utc_now()

    new_toast = %{
      id: id,
      type: toast[:type] || :info,
      title: toast[:title] || "",
      message: toast[:message] || "",
      inserted_at: inserted_at
    }

    toasts =
      [new_toast | socket.assigns.toasts]
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(@max_toasts)

    # Schedule auto-dismiss via the parent LiveView process
    Process.send_after(self(), {:dismiss_toast, id}, 5_000)

    {:ok, assign(socket, :toasts, toasts)}
  end

  def update(%{dismiss: toast_id} = _assigns, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == toast_id))
    {:ok, assign(socket, :toasts, toasts)}
  end

  def update(assigns, socket) do
    {:ok, assign_defaults(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed bottom-6 right-6 z-50 flex flex-col-reverse gap-3 pointer-events-none"
      aria-live="polite"
      aria-label="Notifications"
    >
      <div
        :for={toast <- @toasts}
        id={"toast-#{toast.id}"}
        class={[
          "pointer-events-auto w-80 rounded-lg border p-4 shadow-lg",
          "animate-slide-in-right",
          toast_border_class(toast.type),
          toast_bg_class(toast.type)
        ]}
        role="alert"
      >
        <div class="flex items-start gap-3">
          <div class={["shrink-0 mt-0.5", toast_icon_class(toast.type)]}>
            {toast_icon(toast.type)}
          </div>
          <div class="flex-1 min-w-0">
            <p :if={toast.title != ""} class="text-sm font-medium text-white">
              {toast.title}
            </p>
            <p class={["text-sm", toast_message_class(toast.type)]}>
              {toast.message}
            </p>
          </div>
          <button
            type="button"
            phx-click="dismiss_toast"
            phx-value-toast-id={toast.id}
            phx-target={@myself}
            class="shrink-0 text-gray-500 hover:text-white transition-colors"
            aria-label="Dismiss notification"
          >
            <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                clip-rule="evenodd"
              />
            </svg>
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("dismiss_toast", %{"toast-id" => toast_id}, socket) do
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == toast_id))
    {:noreply, assign(socket, :toasts, toasts)}
  end

  # -- Private helpers --

  defp assign_defaults(socket, assigns) do
    socket
    |> assign(:id, assigns[:id] || socket.assigns[:id] || "toast-stack")
  end

  defp toast_bg_class(:info), do: "bg-gray-800"
  defp toast_bg_class(:success), do: "bg-gray-800"
  defp toast_bg_class(:warning), do: "bg-gray-800"
  defp toast_bg_class(:error), do: "bg-gray-800"

  defp toast_border_class(:info), do: "border-purple-500/50"
  defp toast_border_class(:success), do: "border-green-500/50"
  defp toast_border_class(:warning), do: "border-amber-500/50"
  defp toast_border_class(:error), do: "border-red-500/50"

  defp toast_icon_class(:info), do: "text-purple-400"
  defp toast_icon_class(:success), do: "text-green-400"
  defp toast_icon_class(:warning), do: "text-amber-400"
  defp toast_icon_class(:error), do: "text-red-400"

  defp toast_message_class(:info), do: "text-gray-300"
  defp toast_message_class(:success), do: "text-green-200"
  defp toast_message_class(:warning), do: "text-amber-200"
  defp toast_message_class(:error), do: "text-red-200"

  defp toast_icon(:info) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp toast_icon(:success) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp toast_icon(:warning) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp toast_icon(:error) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end
end
