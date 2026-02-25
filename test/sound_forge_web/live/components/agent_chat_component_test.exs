defmodule SoundForgeWeb.Live.Components.AgentChatComponentTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  alias SoundForgeWeb.Live.Components.AgentChatComponent

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Render the component in isolation using a wrapper LiveView.
  # We use live_isolated/3 to mount the component through a LiveView.

  defmodule WrapperLive do
    use SoundForgeWeb, :live_view

    def render(assigns) do
      ~H"""
      <.live_component
        module={SoundForgeWeb.Live.Components.AgentChatComponent}
        id="chat-test"
        current_user_id={@user_id}
        track_id={nil}
      />
      """
    end

    def mount(_params, session, socket) do
      {:ok, assign(socket, user_id: session["user_id"])}
    end
  end

  # ---------------------------------------------------------------------------
  # mount/1 — initial state
  # ---------------------------------------------------------------------------

  describe "initial render" do
    test "renders the AI Assistant toggle button", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      assert html =~ "AI Assistant"
      refute html =~ "Ask me anything"
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_open event
  # ---------------------------------------------------------------------------

  describe "toggle_open event" do
    test "opens the chat panel on first click", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      html =
        lv
        |> element("[phx-click=toggle_open]")
        |> render_click()

      assert html =~ "Ask me anything"
    end

    test "closes the panel on second click", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      # open
      lv |> element("[phx-click=toggle_open]") |> render_click()
      # close
      html = lv |> element("[phx-click=toggle_open]") |> render_click()

      refute html =~ "Ask me anything"
    end
  end

  # ---------------------------------------------------------------------------
  # send_message event
  # ---------------------------------------------------------------------------

  describe "send_message event" do
    test "empty message is ignored", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      # Open the panel
      lv |> element("[phx-click=toggle_open]") |> render_click()

      # Submit empty message
      html = lv |> form("form[phx-submit=send_message]", %{message: "   "}) |> render_submit()
      # Should not show loading indicator for blank message
      refute html =~ "animate-bounce"
    end

    test "non-empty message adds user message and shows loading", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      lv |> element("[phx-click=toggle_open]") |> render_click()

      html =
        lv
        |> form("form[phx-submit=send_message]", %{message: "What key is this track in?"})
        |> render_submit()

      assert html =~ "What key is this track in?"
      assert html =~ "animate-bounce"
    end
  end

  # ---------------------------------------------------------------------------
  # clear_history event
  # ---------------------------------------------------------------------------

  describe "clear_history event" do
    test "Clear button is absent when no messages", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      lv |> element("[phx-click=toggle_open]") |> render_click()
      html = render(lv)
      # Clear button only shown when messages != []
      refute html =~ "phx-click=\"clear_history\""
    end

    test "messages are cleared after clear_history event", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} =
        live_isolated(conn, WrapperLive, session: %{"user_id" => user.id})

      lv |> element("[phx-click=toggle_open]") |> render_click()

      # Send a message to populate history
      lv
      |> form("form[phx-submit=send_message]", %{message: "test message"})
      |> render_submit()

      # Now clear
      html = lv |> element("[phx-click=clear_history]") |> render_click()
      assert html =~ "Ask me anything"
      refute html =~ "test message"
    end
  end
end
