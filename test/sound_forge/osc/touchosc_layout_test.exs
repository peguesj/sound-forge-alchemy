defmodule SoundForge.OSC.TouchOSCLayoutTest do
  use ExUnit.Case, async: true

  alias SoundForge.OSC.TouchOSCLayout

  describe "generate_xml/0" do
    test "returns valid XML string" do
      xml = TouchOSCLayout.generate_xml()
      assert is_binary(xml)
      assert xml =~ "<?xml version="
      assert xml =~ "<layout"
      assert xml =~ "</layout>"
    end

    test "contains tabpage named Mixer" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(name="Mixer")
    end

    test "contains 8 stem faders" do
      xml = TouchOSCLayout.generate_xml()
      for i <- 1..8 do
        assert xml =~ ~s(name="stem_#{i}_vol"), "Missing stem_#{i}_vol fader"
        assert xml =~ ~s(osc_cs="/stem/#{i}/volume"), "Missing OSC path for stem #{i}"
      end
    end

    test "contains 8 stem labels" do
      xml = TouchOSCLayout.generate_xml()
      for i <- 1..8 do
        assert xml =~ ~s(name="stem_#{i}_label"), "Missing label for stem #{i}"
      end
    end

    test "contains mute and solo buttons for all stems" do
      xml = TouchOSCLayout.generate_xml()
      for i <- 1..8 do
        assert xml =~ ~s(name="stem_#{i}_mute"), "Missing mute for stem #{i}"
        assert xml =~ ~s(name="stem_#{i}_solo"), "Missing solo for stem #{i}"
        assert xml =~ ~s(osc_cs="/stem/#{i}/mute")
        assert xml =~ ~s(osc_cs="/stem/#{i}/solo")
      end
    end

    test "contains transport controls" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(name="play")
      assert xml =~ ~s(name="stop")
      assert xml =~ ~s(name="prev")
      assert xml =~ ~s(name="next")
      assert xml =~ ~s(osc_cs="/transport/play")
      assert xml =~ ~s(osc_cs="/transport/stop")
      assert xml =~ ~s(osc_cs="/transport/prev")
      assert xml =~ ~s(osc_cs="/transport/next")
    end

    test "contains BPM display" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(name="bpm_display")
      assert xml =~ ~s(osc_cs="/bpm")
    end

    test "contains track title label" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(name="track_title")
      assert xml =~ ~s(osc_cs="/track/title")
    end

    test "faders use correct stem colors" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(color="#3B82F6")
      assert xml =~ ~s(color="#EF4444")
      assert xml =~ ~s(color="#22C55E")
    end

    test "uses horizontal orientation" do
      xml = TouchOSCLayout.generate_xml()
      assert xml =~ ~s(orientation="horizontal")
    end
  end
end
