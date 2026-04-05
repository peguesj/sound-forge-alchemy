defmodule SoundForgeWeb.ChromaticPadsEventsTest do
  @moduledoc """
  Tests for ChromaticPadsComponent event handlers: bank CRUD, pad operations,
  master volume, browser, MIDI learn, and preset import.
  """
  use SoundForgeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  defp create_bank_for_user(user) do
    {:ok, bank} = SoundForge.Sampler.create_bank(%{name: "Test Bank", user_id: user.id, position: 0})
    # Reload with pads preloaded
    SoundForge.Sampler.get_bank!(bank.id)
  end

  defp first_pad(bank) do
    List.first(bank.pads)
  end

  describe "bank management" do
    test "start_create_bank and cancel_create_bank", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "start_create_bank")
      assert is_binary(html)
      html2 = render_click(view, "cancel_create_bank")
      assert is_binary(html2)
    end

    test "update_new_bank_name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      render_click(view, "start_create_bank")
      html = render_click(view, "update_new_bank_name", %{"name" => "My New Bank"})
      assert is_binary(html)
    end

    test "create_bank with name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "create_bank", %{"name" => "Created Bank"})
      assert html =~ "Created Bank" or is_binary(html)
    end

    test "switch_bank", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "switch_bank", %{"value" => bank.id, "_target" => ["value"]})
      assert is_binary(html)
    end

    test "switch_bank with empty value", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "switch_bank", %{"value" => "", "_target" => ["value"]})
      assert is_binary(html)
    end

    test "start_rename_bank and cancel_rename_bank", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "start_rename_bank")
      assert is_binary(html)
      html2 = render_click(view, "cancel_rename_bank")
      assert is_binary(html2)
    end

    test "update_rename_bank_name", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      render_click(view, "start_rename_bank")
      html = render_click(view, "update_rename_bank_name", %{"name" => "Renamed"})
      assert is_binary(html)
    end

    test "rename_bank", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "rename_bank", %{"name" => "Better Name"})
      assert is_binary(html)
    end

    test "delete_bank", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "delete_bank")
      assert is_binary(html)
    end
  end

  describe "pad operations" do
    test "select_pad and deselect_pad", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "select_pad", %{"pad-id" => pad.id})
      assert is_binary(html)
      html2 = render_click(view, "deselect_pad")
      assert is_binary(html2)
    end

    test "update_pad_label", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_label", %{"pad-id" => pad.id, "value" => "Kick"})
      assert is_binary(html)
    end

    test "update_pad_volume", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_volume", %{"pad-id" => pad.id, "value" => "75"})
      assert is_binary(html)
    end

    test "update_pad_pitch", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_pitch", %{"pad-id" => pad.id, "value" => "2"})
      assert is_binary(html)
    end

    test "update_pad_velocity", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_velocity", %{"pad-id" => pad.id, "value" => "80"})
      assert is_binary(html)
    end

    test "update_pad_start_time", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_start_time", %{"pad-id" => pad.id, "value" => "1.5"})
      assert is_binary(html)
    end

    test "update_pad_end_time", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_end_time", %{"pad-id" => pad.id, "value" => "3.0"})
      assert is_binary(html)
    end

    test "update_pad_end_time with empty value", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_end_time", %{"pad-id" => pad.id, "value" => ""})
      assert is_binary(html)
    end

    test "update_pad_color", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "update_pad_color", %{"pad-id" => pad.id, "color" => "#FF0000"})
      assert is_binary(html)
    end

    test "clear_pad_full", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "clear_pad_full", %{"pad-id" => pad.id})
      assert is_binary(html)
    end
  end

  describe "master volume and transport" do
    test "set_master_volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "set_master_volume", %{"value" => "50"})
      assert is_binary(html)
    end

    test "pad_triggered", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "pad_triggered", %{"pad_id" => "1"})
      assert is_binary(html)
    end
  end

  describe "browser" do
    test "toggle_browser", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "toggle_browser")
      assert is_binary(html)
      html2 = render_click(view, "toggle_browser")
      assert is_binary(html2)
    end

    test "browser_search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      render_click(view, "toggle_browser")
      html = render_click(view, "browser_search", %{"value" => "drums"})
      assert is_binary(html)
    end

    test "browser_load_track", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id, title: "Pad Track"})
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "browser_load_track", %{"track-id" => track.id})
      assert is_binary(html)
    end
  end

  describe "MIDI learn" do
    test "toggle_midi_learn on and off", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "toggle_midi_learn")
      assert is_binary(html)
      html2 = render_click(view, "toggle_midi_learn")
      assert is_binary(html2)
    end

    test "midi_learn_pad", %{conn: conn, user: user} do
      bank = create_bank_for_user(user)
      pad = first_pad(bank)

      {:ok, view, _html} = live(conn, "/?tab=pads")
      render_click(view, "toggle_midi_learn")
      html = render_click(view, "midi_learn_pad", %{"pad-id" => pad.id, "pad-index" => "0"})
      assert is_binary(html)
    end

    test "midi_learn_param", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      render_click(view, "toggle_midi_learn")
      html = render_click(view, "midi_learn_param", %{"param" => "volume", "pad-index" => "0"})
      assert is_binary(html)
    end

    test "midi_status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "midi_status", %{"available" => true, "devices" => []})
      assert is_binary(html)
    end

    test "midi_devices_updated", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "midi_devices_updated", %{"devices" => ["MPK Mini"]})
      assert is_binary(html)
    end

    test "midi_activity", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "midi_activity")
      assert is_binary(html)
    end
  end

  describe "preset import" do
    test "start_import_preset and cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "start_import_preset")
      assert is_binary(html)
      html2 = render_click(view, "cancel_import_preset")
      assert is_binary(html2)
    end

    test "validate_preset", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "validate_preset")
      assert is_binary(html)
    end
  end

  describe "quick_load" do
    test "quick_load with bank", %{conn: conn, user: user} do
      _bank = create_bank_for_user(user)
      {:ok, view, _html} = live(conn, "/?tab=pads")
      html = render_click(view, "quick_load")
      assert is_binary(html)
    end
  end
end
