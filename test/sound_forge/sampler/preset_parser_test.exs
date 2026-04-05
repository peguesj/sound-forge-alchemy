defmodule SoundForge.Sampler.PresetParserTest do
  use ExUnit.Case, async: true

  alias SoundForge.Sampler.PresetParser

  describe "detect_format/1" do
    test "detects .touchosc" do
      assert PresetParser.detect_format("layout.touchosc") == :touchosc
    end

    test "detects .xpm" do
      assert PresetParser.detect_format("program.xpm") == :mpc_xpm
    end

    test "detects .pgm" do
      assert PresetParser.detect_format("legacy.pgm") == :mpc_pgm
    end

    test "returns :unknown for unrecognized extension" do
      assert PresetParser.detect_format("file.txt") == :unknown
      assert PresetParser.detect_format("file.wav") == :unknown
    end

    test "case insensitive detection" do
      assert PresetParser.detect_format("Layout.TOUCHOSC") == :touchosc
      assert PresetParser.detect_format("Program.XPM") == :mpc_xpm
      assert PresetParser.detect_format("Legacy.PGM") == :mpc_pgm
    end
  end

  describe "parse/2 - format dispatch" do
    test "returns error for unknown format" do
      assert {:error, msg} = PresetParser.parse("data", "file.txt")
      assert msg =~ "Unknown preset format"
    end
  end

  describe "parse_touchosc/1" do
    test "returns error for non-zip data" do
      assert {:error, msg} = PresetParser.parse_touchosc("not a zip")
      assert msg =~ "unzip" or msg =~ "parse error"
    end

    test "returns error for zip without index.xml" do
      {:ok, {_, zip_binary}} = :zip.create(~c"test.zip", [{~c"other.xml", "<root/>"}], [:memory])
      assert {:error, msg} = PresetParser.parse_touchosc(zip_binary)
      assert msg =~ "index.xml"
    end

    test "parses valid touchosc with push controls" do
      index_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <layout>
        <control type="push" name="Pad1" midi_type="1" midi_channel="10" midi_number="36"/>
        <control type="push" name="Pad2" midi_type="1" midi_channel="10" midi_number="37"/>
        <control type="fader" name="Volume1" midi_type="0" midi_channel="1" midi_number="7"/>
        <control type="rotary" name="Pitch1" midi_type="0" midi_channel="1" midi_number="10"/>
      </layout>
      """

      {:ok, {_, zip_binary}} = :zip.create(~c"test.zip", [{~c"index.xml", index_xml}], [:memory])
      assert {:ok, preset} = PresetParser.parse_touchosc(zip_binary)

      assert preset.format == :touchosc
      assert preset.name == "TouchOSC Layout"
      assert length(preset.pads) == 2
      assert length(preset.midi_mappings) == 4

      # First pad
      first_pad = hd(preset.pads)
      assert first_pad.index == 0
      assert first_pad.label == "Pad1"
      assert first_pad.midi_note == 36
    end

    test "limits pads to 16" do
      pads =
        for i <- 0..20 do
          ~s(<control type="push" name="Pad#{i}" midi_type="1" midi_channel="10" midi_number="#{36 + i}"/>)
        end
        |> Enum.join("\n")

      index_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <layout>#{pads}</layout>
      """

      {:ok, {_, zip_binary}} = :zip.create(~c"test.zip", [{~c"index.xml", index_xml}], [:memory])
      {:ok, preset} = PresetParser.parse_touchosc(zip_binary)
      assert length(preset.pads) == 16
    end

    test "recognizes fader parameter types" do
      index_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <layout>
        <control type="faderv" name="MasterVol" midi_type="0" midi_channel="1" midi_number="7"/>
        <control type="faderh" name="Crossfader" midi_type="0" midi_channel="1" midi_number="8"/>
      </layout>
      """

      {:ok, {_, zip_binary}} = :zip.create(~c"test.zip", [{~c"index.xml", index_xml}], [:memory])
      {:ok, preset} = PresetParser.parse_touchosc(zip_binary)

      mappings = preset.midi_mappings
      master = Enum.find(mappings, &(&1.midi_number == 7))
      crossfader = Enum.find(mappings, &(&1.midi_number == 8))

      assert master.parameter_type == :master_volume
      assert crossfader.parameter_type == :crossfader
    end
  end

  describe "parse_mpc_xpm/1" do
    test "parses valid XPM XML" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <ProgramName>Test Kit</ProgramName>
        <Pad number="0">
          <SampleName>kick_01.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
        <Pad number="1">
          <SampleName>snare_01.wav</SampleName>
          <RootNote>38</RootNote>
          <Level>90</Level>
          <Tune>2</Tune>
          <Pan>60</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      assert {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert preset.format == :mpc_xpm
      assert preset.name == "Test Kit"
      assert length(preset.pads) == 2

      first = hd(preset.pads)
      assert first.index == 0
      assert first.label == "kick_01"
      assert first.sample_name == "kick_01.wav"
      assert first.midi_note == 36
      assert first.play_mode == :one_shot
    end

    test "handles loop play mode" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>loop.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>LOOP</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert hd(preset.pads).play_mode == :loop
    end

    test "returns error for invalid XML" do
      assert {:error, msg} = PresetParser.parse_mpc_xpm("not xml at all {{{")
      assert msg =~ "parse" or msg =~ "error"
    end

    test "generates midi_mappings from pads" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>kick.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert length(preset.midi_mappings) == 1
      mapping = hd(preset.midi_mappings)
      assert mapping.midi_type == :note
      assert mapping.midi_number == 36
      assert mapping.parameter_type == :pad_trigger
    end
  end

  describe "parse_mpc_pgm/1" do
    test "returns error for too-small binary" do
      assert {:error, msg} = PresetParser.parse_mpc_pgm(<<0, 1, 2>>)
      assert msg =~ "too small"
    end

    test "parses valid PGM binary" do
      # Build a minimal PGM: 8-byte header + one 24-byte pad entry
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>

      # Pad entry: 16 bytes sample name + volume + pan + tune + play_mode + midi_note + 3 reserved
      sample_name = "kick" <> String.duplicate(<<0>>, 12)
      pad_entry = sample_name <> <<100, 64, 0, 0, 36, 0, 0, 0>>

      binary = header <> pad_entry

      assert {:ok, preset} = PresetParser.parse_mpc_pgm(binary)
      assert preset.format == :mpc_pgm
      assert preset.name == "MPC Legacy Program"
      assert length(preset.pads) >= 1

      first = hd(preset.pads)
      assert first.label == "kick"
      assert first.midi_note == 36
      assert first.play_mode == :one_shot
    end

    test "parses PGM with loop play mode" do
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      sample_name = "loop" <> String.duplicate(<<0>>, 12)
      # play_mode byte = 1 means loop
      pad_entry = sample_name <> <<100, 64, 0, 1, 36, 0, 0, 0>>

      {:ok, preset} = PresetParser.parse_mpc_pgm(header <> pad_entry)
      assert hd(preset.pads).play_mode == :loop
    end

    test "parses PGM volume and pan correctly" do
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      sample_name = "snare" <> String.duplicate(<<0>>, 11)
      # volume=127 (max), pan=0 (hard left), tune=+5, one_shot, midi=38
      pad_entry = sample_name <> <<127, 0, 5, 0, 38, 0, 0, 0>>

      {:ok, preset} = PresetParser.parse_mpc_pgm(header <> pad_entry)
      first = hd(preset.pads)

      assert first.volume == Float.round(127 / 127.0, 4)
      assert first.pan == 0.0
      assert first.pitch == 5.0
      assert first.midi_note == 38
    end

    test "parses multiple PGM pad entries" do
      header = <<0, 0, 0, 0, 2, 0, 0, 0>>

      pad1 = ("kick" <> String.duplicate(<<0>>, 12)) <> <<100, 64, 0, 0, 36, 0, 0, 0>>
      pad2 = ("snare" <> String.duplicate(<<0>>, 11)) <> <<90, 64, 0, 0, 38, 0, 0, 0>>

      {:ok, preset} = PresetParser.parse_mpc_pgm(header <> pad1 <> pad2)
      assert length(preset.pads) == 2
      assert length(preset.midi_mappings) == 2

      labels = Enum.map(preset.pads, & &1.label)
      assert "kick" in labels
      assert "snare" in labels
    end

    test "PGM pad with empty sample name gets default label" do
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      # 16 null bytes for empty sample name
      sample_name = String.duplicate(<<0>>, 16)
      pad_entry = sample_name <> <<100, 64, 0, 0, 36, 0, 0, 0>>

      {:ok, preset} = PresetParser.parse_mpc_pgm(header <> pad_entry)
      first = hd(preset.pads)

      assert first.label == "Pad 1"
      assert is_nil(first.sample_name)
    end

    test "generates midi_mappings from PGM pads" do
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      sample_name = "hihat" <> String.duplicate(<<0>>, 11)
      pad_entry = sample_name <> <<80, 64, 0, 0, 42, 0, 0, 0>>

      {:ok, preset} = PresetParser.parse_mpc_pgm(header <> pad_entry)
      assert length(preset.midi_mappings) == 1

      mapping = hd(preset.midi_mappings)
      assert mapping.midi_type == :note
      assert mapping.midi_number == 42
      assert mapping.parameter_type == :pad_trigger
      assert mapping.parameter_index == 0
    end
  end

  describe "parse_mpc_xpm/1 additional cases" do
    test "handles gate play mode" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>pad.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>GATE</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert hd(preset.pads).play_mode == :gate
    end

    test "handles alternative one_shot spellings" do
      for spelling <- ["ONE_SHOT", "ONESHOT", "ONE SHOT"] do
        xpm_xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Program>
          <Pad number="0">
            <SampleName>test.wav</SampleName>
            <RootNote>36</RootNote>
            <Level>100</Level>
            <Tune>0</Tune>
            <Pan>50</Pan>
            <PlayMode>#{spelling}</PlayMode>
          </Pad>
        </Program>
        """

        {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
        assert hd(preset.pads).play_mode == :one_shot,
               "Expected :one_shot for '#{spelling}'"
      end
    end

    test "defaults program name to MPC Program when missing" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>kick.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert preset.name == "MPC Program"
    end

    test "normalizes volume and pan values" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>test.wav</SampleName>
          <RootNote>60</RootNote>
          <Level>64</Level>
          <Tune>-5</Tune>
          <Pan>100</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      pad = hd(preset.pads)

      assert pad.volume == Float.round(64 / 127.0, 4)
      assert pad.pan == 1.0
      assert pad.pitch == -5.0
    end

    test "pad without sample name gets default label" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="3">
          <SampleName></SampleName>
          <RootNote>39</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      pad = hd(preset.pads)

      assert pad.label == "Pad 4"
      assert is_nil(pad.sample_name)
    end

    test "limits pads to 16" do
      pads =
        for i <- 0..20 do
          """
          <Pad number="#{i}">
            <SampleName>pad_#{i}.wav</SampleName>
            <RootNote>#{36 + i}</RootNote>
            <Level>100</Level>
            <Tune>0</Tune>
            <Pan>50</Pan>
            <PlayMode>ONE_SHOT</PlayMode>
          </Pad>
          """
        end
        |> Enum.join("\n")

      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <ProgramName>Big Kit</ProgramName>
        #{pads}
      </Program>
      """

      {:ok, preset} = PresetParser.parse_mpc_xpm(xpm_xml)
      assert length(preset.pads) == 16
    end
  end

  describe "parse/2 dispatch" do
    test "dispatches .xpm to parse_mpc_xpm" do
      xpm_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Program>
        <Pad number="0">
          <SampleName>kick.wav</SampleName>
          <RootNote>36</RootNote>
          <Level>100</Level>
          <Tune>0</Tune>
          <Pan>50</Pan>
          <PlayMode>ONE_SHOT</PlayMode>
        </Pad>
      </Program>
      """

      assert {:ok, preset} = PresetParser.parse(xpm_xml, "my_kit.xpm")
      assert preset.format == :mpc_xpm
    end

    test "dispatches .pgm to parse_mpc_pgm" do
      header = <<0, 0, 0, 0, 1, 0, 0, 0>>
      sample_name = "kick" <> String.duplicate(<<0>>, 12)
      pad_entry = sample_name <> <<100, 64, 0, 0, 36, 0, 0, 0>>

      assert {:ok, preset} = PresetParser.parse(header <> pad_entry, "legacy.pgm")
      assert preset.format == :mpc_pgm
    end
  end

  describe "detect_format/1 additional cases" do
    test "handles filenames with path" do
      assert PresetParser.detect_format("/path/to/layout.touchosc") == :touchosc
      assert PresetParser.detect_format("C:\\Users\\kit.xpm") == :mpc_xpm
    end

    test "handles filename without extension" do
      assert PresetParser.detect_format("noextension") == :unknown
    end

    test "handles empty string" do
      assert PresetParser.detect_format("") == :unknown
    end
  end
end
