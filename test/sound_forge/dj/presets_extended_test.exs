defmodule SoundForge.DJ.PresetsExtendedTest do
  @moduledoc "Extended tests for DJ Presets parsing - variants and edge cases."
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Presets

  describe "parse_tsi/2 crossfader variants" do
    test "parses mixer.xfader control" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>20</MidiNote><Channel>0</Channel>
          <ControlId>mixer.xfader</ControlId><DeviceName>XF</DeviceName><Type>cc</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_crossfader
    end
  end

  describe "parse_tsi/2 volume" do
    test "parses deck.volume as stem_volume" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>30</MidiNote><Channel>1</Channel>
          <ControlId>deck.volume</ControlId><DeviceName>Vol</DeviceName><Type>cc</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :stem_volume
      assert m.channel == 1
      assert m.params["target"] == "master"
    end
  end

  describe "parse_tsi/2 sync" do
    test "parses deck.sync as dj_pitch" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>18</MidiNote><Channel>0</Channel>
          <ControlId>deck.sync</ControlId><DeviceName>Sync</DeviceName><Type>note</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_pitch
      assert m.midi_type == :note_on
    end
  end

  describe "parse_tsi/2 cup variant" do
    test "parses deck.cup as dj_cue" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>51</MidiNote><Channel>0</Channel>
          <ControlId>deck.cup</ControlId><DeviceName>Cup</DeviceName><Type>note</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_cue
    end
  end

  describe "parse_tsi/2 deck assignment" do
    test "assigns deck from Deck attribute A" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>0</Channel>
          <ControlId>deck.play</ControlId><DeviceName>T</DeviceName><Deck>A</Deck>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.params["deck"] == "1"
    end

    test "assigns deck from Deck attribute B" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>61</MidiNote><Channel>0</Channel>
          <ControlId>deck.play</ControlId><DeviceName>T</DeviceName><Deck>B</Deck>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.params["deck"] == "2"
    end
  end

  describe "parse_tsi/2 multiple entries" do
    test "parses all recognized entries" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>0</Channel>
          <ControlId>deck.play</ControlId><DeviceName>M</DeviceName></Entry>
        <Entry><MidiNote>61</MidiNote><Channel>0</Channel>
          <ControlId>deck.cue</ControlId><DeviceName>M</DeviceName></Entry>
        <Entry><MidiNote>62</MidiNote><Channel>0</Channel>
          <ControlId>mixer.crossfader</ControlId><DeviceName>M</DeviceName></Entry>
      </Controller>
      """
      assert {:ok, %{mappings: mappings}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert length(mappings) == 3
    end
  end

  describe "parse_tsi/2 note_off type" do
    test "parses note_off midi type" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>0</Channel>
          <ControlId>deck.play</ControlId><DeviceName>T</DeviceName><Type>note_off</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.midi_type == :note_off
    end
  end

  describe "parse_tsi/2 deck_a prefix normalization" do
    test "normalizes deck_a prefix" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>0</Channel>
          <ControlId>deck_a.play</ControlId><DeviceName>NI</DeviceName>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_play
      assert m.params["deck"] == "1"
    end
  end

  describe "parse_tsi/2 user_id and source" do
    test "assigns user_id and source correctly" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>0</Channel>
          <ControlId>deck.play</ControlId><DeviceName>T</DeviceName>
        </Entry>
      </Controller>
      """
      uid = Ecto.UUID.generate()
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, uid)
      assert m.user_id == uid
      assert m.source == "tsi"
    end
  end

  describe "parse_tsi/2 channel clamping" do
    test "clamps channel above 15" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>60</MidiNote><Channel>20</Channel>
          <ControlId>deck.play</ControlId><DeviceName>T</DeviceName>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.channel <= 15
    end
  end

  describe "parse_tsi/2 hotcue variants" do
    test "parses hotcue_2 with correct slot" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>11</MidiNote><Channel>0</Channel>
          <ControlId>deck.hotcue_2</ControlId><DeviceName>HC</DeviceName><Type>cc</Type>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_cue
      assert m.params["slot"] == "2"
    end

    test "parses hotcue_8 with correct slot" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Controller>
        <Entry><MidiNote>18</MidiNote><Channel>0</Channel>
          <ControlId>deck.hotcue_8</ControlId><DeviceName>HC</DeviceName>
        </Entry>
      </Controller>
      """
      assert {:ok, %{mappings: [m]}} = Presets.parse_tsi(xml, Ecto.UUID.generate())
      assert m.action == :dj_cue
      assert m.params["slot"] == "8"
    end
  end
end
