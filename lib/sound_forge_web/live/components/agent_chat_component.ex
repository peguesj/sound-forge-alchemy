defmodule SoundForgeWeb.Live.Components.AgentChatComponent do
  @moduledoc """
  LiveComponent providing a conversational chat interface to the SFA Agent Orchestrator.

  Renders a floating chat panel where users can type natural-language instructions
  that are routed to the appropriate specialist agent. Displays streaming-style
  responses, usage stats, and a message history for the session.

  ## Usage

      <.live_component
        module={SoundForgeWeb.Live.Components.AgentChatComponent}
        id="agent-chat"
        current_user_id={@current_user_id}
        track_id={@selected_track_id}
      />
  """

  use SoundForgeWeb, :live_component

  alias SoundForge.Agents.{Context, Orchestrator}

  @max_history 50

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:input, "")
     |> assign(:loading, false)
     |> assign(:open, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign_new(:messages, fn -> [] end)
      |> assign_new(:input, fn -> "" end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:open, fn -> false end)
      |> assign(:current_user_id, assigns[:current_user_id])
      |> assign(:track_id, assigns[:track_id])

    socket =
      case assigns[:reply] do
        {:ok, result} ->
          msg = %{
            role: :agent,
            content: result.content || "(no response)",
            agent: result.agent,
            id: System.unique_integer([:positive])
          }

          socket
          |> assign(:messages, append_message(socket.assigns.messages, msg))
          |> assign(:loading, false)

        {:error, reason} ->
          msg = %{
            role: :error,
            content: "Agent error: #{inspect(reason)}",
            id: System.unique_integer([:positive])
          }

          socket
          |> assign(:messages, append_message(socket.assigns.messages, msg))
          |> assign(:loading, false)

        nil ->
          socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_open", _params, socket) do
    {:noreply, assign(socket, :open, !socket.assigns.open)}
  end

  @impl true
  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      user_msg = %{role: :user, content: message, id: System.unique_integer([:positive])}
      messages = append_message(socket.assigns.messages, user_msg)

      # Agent runs async in TaskSupervisor; result forwarded to parent LV via send_update
      component_id = socket.assigns.id
      user_id = socket.assigns[:current_user_id]
      track_id = socket.assigns[:track_id]
      component_module = __MODULE__

      Task.Supervisor.async_nolink(SoundForge.TaskSupervisor, fn ->
        ctx = Context.new(message, user_id: user_id, track_id: track_id)
        result = Orchestrator.run(ctx)
        Phoenix.LiveView.send_update(component_module, id: component_id, reply: result)
      end)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:input, "")
       |> assign(:loading, true)}
    end
  end

  @impl true
  def handle_event("clear_history", _params, socket) do
    {:noreply, assign(socket, :messages, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-20 right-4 z-50 flex flex-col items-end gap-2">
      <!-- Toggle button -->
      <button
        phx-click="toggle_open"
        phx-target={@myself}
        class={[
          "flex items-center gap-2 px-4 py-2.5 rounded-full text-sm font-medium shadow-lg transition-all",
          if(@open,
            do: "bg-purple-600 text-white hover:bg-purple-700",
            else: "bg-gray-800 text-gray-200 hover:bg-gray-700 border border-gray-700"
          )
        ]}
        title="AI Assistant"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.346.346a3.99 3.99 0 01-1.122.83l-.026.013A4.003 4.003 0 0112 18a4 4 0 01-1.953-.514l-.026-.013a4.003 4.003 0 01-1.122-.83l-.347-.347z" />
        </svg>
        {if @open, do: "Close AI", else: "AI Assistant"}
      </button>

      <!-- Chat panel -->
      <div
        :if={@open}
        class="w-80 sm:w-96 bg-gray-900 border border-gray-700 rounded-2xl shadow-2xl flex flex-col overflow-hidden"
        style="max-height: 520px;"
      >
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 bg-gray-800 border-b border-gray-700">
          <div class="flex items-center gap-2">
            <div class="w-2 h-2 rounded-full bg-purple-400 animate-pulse"></div>
            <span class="text-sm font-medium text-white">AI Assistant</span>
          </div>
          <button
            :if={@messages != []}
            phx-click="clear_history"
            phx-target={@myself}
            class="text-xs text-gray-500 hover:text-gray-300"
          >
            Clear
          </button>
        </div>

        <!-- Messages -->
        <div
          id={"#{@id}-messages"}
          class="flex-1 overflow-y-auto p-3 space-y-3 min-h-0"
          phx-hook="ScrollToBottom"
        >
          <!-- Empty state -->
          <div :if={@messages == []} class="flex flex-col items-center justify-center h-32 text-center">
            <p class="text-xs text-gray-500">Ask me anything about your tracks,<br/>mixing, stems, or mastering.</p>
          </div>

          <!-- Message list -->
          <div :for={msg <- @messages} class={[
            "flex",
            if(msg.role == :user, do: "justify-end", else: "justify-start")
          ]}>
            <div class={[
              "max-w-xs rounded-xl px-3 py-2 text-sm",
              case msg.role do
                :user -> "bg-purple-600 text-white rounded-br-sm"
                :agent -> "bg-gray-800 text-gray-200 rounded-bl-sm border border-gray-700"
                :error -> "bg-red-900/40 text-red-300 border border-red-700/50 rounded-bl-sm"
              end
            ]}>
              <p :if={msg.role == :agent} class="text-xs text-gray-500 mb-1">
                {agent_label(msg[:agent])}
              </p>
              <p class="whitespace-pre-wrap leading-relaxed">{msg.content}</p>
            </div>
          </div>

          <!-- Typing indicator -->
          <div :if={@loading} class="flex justify-start">
            <div class="bg-gray-800 border border-gray-700 rounded-xl rounded-bl-sm px-3 py-2">
              <div class="flex gap-1 items-center h-4">
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
                <div class="w-1.5 h-1.5 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
              </div>
            </div>
          </div>
        </div>

        <!-- Input -->
        <div class="border-t border-gray-700 p-3">
          <form
            phx-submit="send_message"
            phx-target={@myself}
            class="flex gap-2"
          >
            <input
              type="text"
              name="message"
              value={@input}
              phx-change="update_input"
              phx-target={@myself}
              placeholder="Ask about key, BPM, mix planning..."
              autocomplete="off"
              disabled={@loading}
              class="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:border-purple-500 focus:outline-none disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={@loading || String.trim(@input) == ""}
              class="p-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3" />
              </svg>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp append_message(messages, msg) do
    (messages ++ [msg]) |> Enum.take(-@max_history)
  end

  defp agent_label(nil), do: "Assistant"
  defp agent_label(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.replace("Agent", "")
    |> String.replace(~r/([A-Z])/, " \\1")
    |> String.trim()
  end
end
