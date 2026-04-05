defmodule SoundForge.DJ.TimecodeTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Timecode

  describe "ms_to_smpte/1" do
    test "0 ms returns 00:00:00:00" do
      assert Timecode.ms_to_smpte(0) == "00:00:00:00"
    end

    test "1000 ms returns 00:00:01:00" do
      assert Timecode.ms_to_smpte(1000) == "00:00:01:00"
    end

    test "61500 ms returns 00:01:01:15" do
      assert Timecode.ms_to_smpte(61_500) == "00:01:01:15"
    end

    test "one hour" do
      assert Timecode.ms_to_smpte(3_600_000) == "01:00:00:00"
    end

    test "negative returns 00:00:00:00" do
      assert Timecode.ms_to_smpte(-100) == "00:00:00:00"
    end

    test "non-number returns 00:00:00:00" do
      assert Timecode.ms_to_smpte(:invalid) == "00:00:00:00"
    end

    test "float input" do
      result = Timecode.ms_to_smpte(500.0)
      assert is_binary(result)
      assert String.match?(result, ~r/^\d{2}:\d{2}:\d{2}:\d{2}$/)
    end

    test "large value" do
      result = Timecode.ms_to_smpte(7_200_000)
      assert result == "02:00:00:00"
    end
  end

  describe "fps/0" do
    test "returns 30" do
      assert Timecode.fps() == 30
    end
  end
end
