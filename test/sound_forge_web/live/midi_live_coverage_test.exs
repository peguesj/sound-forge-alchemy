defmodule SoundForgeWeb.MidiLiveCoverageTest do
  @moduledoc "Tests for MidiLive: mount, tab switching, learn mode, mapping events."
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "mount" do
    test "renders MIDI settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/midi")
      assert html =~ "MIDI"
    end
  end

  describe "tab switching" do
    test "switches to overview tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_tab", %{"tab" => "overview"})
      assert is_binary(html)
    end

    test "switches to mappings tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_tab", %{"tab" => "mappings"})
      assert is_binary(html)
    end

    test "switches to monitor tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_tab", %{"tab" => "monitor"})
      assert is_binary(html)
    end
  end

  describe "learn mode" do
    test "start_learn without selected device", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "start_learn", %{})
      assert is_binary(html)
    end

    test "cancel_learn", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "cancel_learn", %{})
      assert is_binary(html)
    end
  end

  describe "select events" do
    test "select_action with empty string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_action", %{"action" => ""})
      assert is_binary(html)
    end

    test "select_action with valid action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_action", %{"action" => "play"})
      assert is_binary(html)
    end

    test "select_device with empty string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_device", %{"device" => ""})
      assert is_binary(html)
    end

    test "select_device with device name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "select_device", %{"device" => "MPC Live II"})
      assert is_binary(html)
    end
  end

  describe "mapping events" do
    test "save_mapping without all fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "save_mapping", %{})
      assert is_binary(html)
    end

    test "scan_network", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "scan_network", %{})
      assert is_binary(html)
    end
  end

  describe "monitor events" do
    test "toggle_monitor_listen on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "toggle_monitor_listen", %{})
      assert is_binary(html)
    end

    test "clear_monitor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "clear_monitor", %{})
      assert is_binary(html)
    end
  end

  describe "preset loading" do
    test "load_preset with mpc preset", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      html = render_click(view, "load_preset", %{"preset" => "mpc"})
      assert is_binary(html)
    end
  end

  describe "handle_info" do
    test "midi_device_connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:midi_device_connected, %{port_id: "input:99", name: "Test", direction: :input, type: :usb, status: :connected}})
      html = render(view)
      assert is_binary(html)
    end

    test "midi_device_disconnected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:midi_device_disconnected, %{port_id: "input:99", name: "Test", direction: :input, type: :usb, status: :disconnected}})
      html = render(view)
      assert is_binary(html)
    end

    test "network_device_appeared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:network_device_appeared, %{id: "net-1", name: "NetMIDI", host: "192.168.1.10", port: 5004}})
      html = render(view)
      assert is_binary(html)
    end

    test "network_device_disappeared", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:network_device_disappeared, %{id: "net-1"}})
      html = render(view)
      assert is_binary(html)
    end

    test "clear_activity message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:clear_activity, "input:0"})
      html = render(view)
      assert is_binary(html)
    end

    test "unknown message ignored", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/midi")
      send(view.pid, {:something_unknown, :data})
      html = render(view)
      assert is_binary(html)
    end
  end
end
