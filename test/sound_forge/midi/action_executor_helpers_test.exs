defmodule SoundForge.MIDI.ActionExecutorHelpersTest do
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.ActionExecutor

  describe "cc_to_float/1" do
    test "converts 0 to 0.0" do
      assert ActionExecutor.cc_to_float(0) == 0.0
    end

    test "converts 127 to 1.0" do
      assert ActionExecutor.cc_to_float(127) == 1.0
    end

    test "converts 64 to approximately 0.5" do
      result = ActionExecutor.cc_to_float(64)
      assert_in_delta result, 0.5039, 0.001
    end

    test "clamps values above 127 to 1.0" do
      assert ActionExecutor.cc_to_float(200) == 1.0
      assert ActionExecutor.cc_to_float(255) == 1.0
    end

    test "returns 0.0 for non-integer input" do
      assert ActionExecutor.cc_to_float(-1) == 0.0
      assert ActionExecutor.cc_to_float(nil) == 0.0
    end

    test "result is rounded to 4 decimal places" do
      result = ActionExecutor.cc_to_float(1)
      assert result == Float.round(1 / 127.0, 4)
    end

    test "all valid MIDI CC values produce 0.0..1.0 range" do
      for v <- 0..127 do
        result = ActionExecutor.cc_to_float(v)
        assert result >= 0.0 and result <= 1.0, "cc_to_float(#{v}) = #{result} out of range"
      end
    end
  end
end
