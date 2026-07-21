defmodule SoundForge.DJ.PresetsCoverageTest do
  @moduledoc "Tests for DJ.Presets TSI/TouchOSC parsing."
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Presets

  describe "parse_tsi/2" do
    test "invalid XML returns error" do
      assert {:error, _} = Presets.parse_tsi("not xml at all", "user-1")
    end

    test "empty XML returns ok with empty list" do
      xml = ~s(<?xml version="1.0"?><TSI></TSI>)
      assert {:ok, %{mappings: mappings}} = Presets.parse_tsi(xml, "user-1")
      assert is_list(mappings)
    end

    test "valid XML with Entry containing MidiNote and ControlId" do
      xml = """
      <?xml version="1.0"?>
      <TSI>
        <Entry>
          <MidiNote>60</MidiNote>
          <Channel>0</Channel>
          <ControlId>deck.play</ControlId>
          <DeviceName>Test Controller</DeviceName>
          <Type>note</Type>
          <Deck>A</Deck>
        </Entry>
      </TSI>
      """

      assert {:ok, %{mappings: mappings}} = Presets.parse_tsi(xml, "user-1")
      assert is_list(mappings)
    end

    test "Entry with unknown control is skipped" do
      xml = """
      <?xml version="1.0"?>
      <TSI>
        <Entry>
          <MidiNote>40</MidiNote>
          <Channel>1</Channel>
          <ControlId>completely.unknown.control</ControlId>
          <DeviceName>Unknown</DeviceName>
          <Type>cc</Type>
        </Entry>
      </TSI>
      """

      assert {:ok, %{mappings: mappings}} = Presets.parse_tsi(xml, "user-1")
      assert mappings == []
    end

    test "Entry without MidiNote is skipped" do
      xml = """
      <?xml version="1.0"?>
      <TSI>
        <Entry>
          <ControlId>deck.play</ControlId>
          <Channel>0</Channel>
        </Entry>
      </TSI>
      """

      assert {:ok, %{mappings: mappings}} = Presets.parse_tsi(xml, "user-1")
      assert mappings == []
    end
  end

  describe "parse_touchosc/2" do
    test "invalid binary returns error" do
      assert {:error, _} = Presets.parse_touchosc("not a zip", "user-1")
    end
  end
end
