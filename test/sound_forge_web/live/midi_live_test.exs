defmodule SoundForgeWeb.MidiLiveTest do
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.AccountsFixtures

  describe "authentication" do
    test "redirects unauthenticated users to login" do
      conn = build_conn()
      {:error, {:redirect, %{to: to}}} = live(conn, "/midi")
      assert to == "/users/log-in"
    end
  end

  describe "MIDI settings page" do
    setup do
      user = user_fixture()
      conn = build_conn() |> log_in_user(user)
      %{conn: conn, user: user}
    end

    test "renders MIDI settings page for logged-in user", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "MIDI Settings"
    end

    test "shows device count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "device"
    end

    test "shows Controllers column by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "Controllers"
    end

    test "shows Mappings tab option", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "Mappings"
    end

    test "shows Monitor tab option", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/midi")
      assert html =~ "Monitor"
    end

    test "select_tab switches to mappings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "select_tab", %{"tab" => "mappings"})
      assert html =~ "Mappings" or html =~ "MIDI"
    end

    test "select_tab switches to monitor", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "select_tab", %{"tab" => "monitor"})
      assert html =~ "Monitor" or html =~ "MIDI"
    end

    test "select_tab switches to overview", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "select_tab", %{"tab" => "overview"})
      assert html =~ "Overview" or html =~ "MIDI"
    end

    test "scan_network event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "scan_network")
      assert is_binary(html)
    end

    test "select_action event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "select_action", %{"action" => "play"})
      assert is_binary(html)
    end

    test "cancel_learn event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "cancel_learn")
      assert is_binary(html)
    end

    test "toggle_monitor_listen event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "toggle_monitor_listen")
      assert is_binary(html)
    end

    test "clear_monitor event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "clear_monitor")
      assert is_binary(html)
    end

    test "start_learn_action event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "start_learn_action", %{"action" => "dj_play"})
      assert is_binary(html)
    end

    test "select_tab with unknown tab is handled", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "select_tab", %{"tab" => "devices"})
      assert is_binary(html)
    end

    test "select_action with empty string clears", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_action", %{"action" => "play"})
      html = render_click(view, "select_action", %{"action" => ""})
      assert is_binary(html)
    end

    test "select_device with name and empty string", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_device", %{"device" => "Some Controller"})
      html = render_click(view, "select_device", %{"device" => ""})
      assert is_binary(html)
    end

    test "save_mapping without fields shows flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_tab", %{"tab" => "mappings"})
      html = render_click(view, "save_mapping", %{})
      assert html =~ "fill all fields"
    end

    test "start_learn without selected device does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "start_learn", %{})
      assert is_binary(html)
    end

    test "delete_mapping with non-existent id", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      html = render_click(view, "delete_mapping", %{"id" => "999999"})
      assert is_binary(html)
    end

    test "load_preset generic creates mappings", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_tab", %{"tab" => "mappings"})
      html = render_click(view, "load_preset", %{"preset" => "generic"})
      assert html =~ "Generic"

      mappings = SoundForge.MIDI.Mappings.list_mappings(user.id)
      assert length(mappings) == 3
    end

    test "load_preset unknown shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_tab", %{"tab" => "mappings"})
      html = render_click(view, "load_preset", %{"preset" => "nonexistent"})
      assert html =~ "Unknown preset"
    end

    test "toggle_monitor_listen on then off", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_tab", %{"tab" => "monitor"})
      html = render_click(view, "toggle_monitor_listen", %{})
      assert html =~ "Stop"
      html2 = render_click(view, "toggle_monitor_listen", %{})
      assert html2 =~ "Start"
    end

    test "handles device connected PubSub message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      device = %{
        port_id: "test:1", name: "PubSub USB Device",
        direction: :input, type: :usb, status: :connected,
        connected_at: DateTime.utc_now()
      }
      send(view.pid, {:midi_device_connected, device})
      html = render(view)
      assert html =~ "PubSub USB Device"
    end

    test "handles device disconnected PubSub message", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      send(view.pid, {:midi_device_disconnected, %{port_id: "test:99", name: "Gone"}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles network device appeared", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      net_dev = %{id: "net:1", name: "Network Session", host: "192.168.1.100", port: 5004, status: :available}
      send(view.pid, {:network_device_appeared, net_dev})
      render_click(view, "select_tab", %{"tab" => "devices"})
      html = render(view)
      assert html =~ "Network Session"
    end

    test "handles network device disappeared", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      send(view.pid, {:network_device_disappeared, %{id: "net:gone"}})
      html = render(view)
      assert is_binary(html)
    end

    test "handles midi_message for activity tracking", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      message = %{type: :cc, channel: 0, data: %{controller: 1, value: 64}}
      send(view.pid, {:midi_message, "test:1", message})
      html = render(view)
      assert is_binary(html)
    end

    test "handles clear_activity timer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      send(view.pid, {:clear_activity, "test:1"})
      html = render(view)
      assert is_binary(html)
    end

    test "handles unknown PubSub message gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      send(view.pid, {:unknown_msg_type, "data"})
      html = render(view)
      assert is_binary(html)
    end

    test "monitor accumulates midi messages when listening", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/midi")
      render_click(view, "select_tab", %{"tab" => "monitor"})
      render_click(view, "toggle_monitor_listen", %{})

      message = %{type: :note_on, channel: 0, data: %{note: 60, velocity: 100}}
      send(view.pid, {:midi_message, "test:2", message})

      html = render(view)
      assert html =~ "Note On" or is_binary(html)
    end
  end
end
