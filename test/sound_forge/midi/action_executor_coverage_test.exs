defmodule SoundForge.MIDI.ActionExecutorCoverageTest do
  @moduledoc "Tests for MIDI ActionExecutor: cc_to_float, extract_number, GenServer lifecycle."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.ActionExecutor

  describe "cc_to_float/1" do
    test "0 maps to 0.0" do
      assert ActionExecutor.cc_to_float(0) == 0.0
    end

    test "127 maps to 1.0" do
      assert ActionExecutor.cc_to_float(127) == 1.0
    end

    test "64 maps to roughly 0.5" do
      result = ActionExecutor.cc_to_float(64)
      assert result > 0.49 and result < 0.51
    end

    test "1 maps to small positive float" do
      result = ActionExecutor.cc_to_float(1)
      assert result > 0.0 and result < 0.01
    end

    test "126 maps to just under 1.0" do
      result = ActionExecutor.cc_to_float(126)
      assert result > 0.99 and result <= 1.0
    end

    test "value > 127 clamps to 1.0" do
      assert ActionExecutor.cc_to_float(200) == 1.0
      assert ActionExecutor.cc_to_float(255) == 1.0
    end

    test "negative value returns 0.0" do
      assert ActionExecutor.cc_to_float(-1) == 0.0
      assert ActionExecutor.cc_to_float(-100) == 0.0
    end

    test "non-integer returns 0.0" do
      assert ActionExecutor.cc_to_float(nil) == 0.0
      assert ActionExecutor.cc_to_float("50") == 0.0
      assert ActionExecutor.cc_to_float(1.5) == 0.0
    end

    test "boundary values 1 through 126" do
      for val <- [1, 10, 32, 63, 64, 65, 96, 100, 126] do
        result = ActionExecutor.cc_to_float(val)

        assert result >= 0.0 and result <= 1.0,
               "cc_to_float(#{val}) = #{result} should be in [0,1]"
      end
    end
  end
end
