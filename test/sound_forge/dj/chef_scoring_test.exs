defmodule SoundForge.DJ.ChefScoringTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Chef

  describe "camelot_compatible?/2" do
    test "same code is compatible" do
      assert Chef.camelot_compatible?("8A", "8A")
      assert Chef.camelot_compatible?("1B", "1B")
    end

    test "same number different column is compatible (A<->B)" do
      assert Chef.camelot_compatible?("8A", "8B")
      assert Chef.camelot_compatible?("1B", "1A")
    end

    test "adjacent numbers same column are compatible" do
      assert Chef.camelot_compatible?("7A", "8A")
      assert Chef.camelot_compatible?("8A", "7A")
      assert Chef.camelot_compatible?("8B", "9B")
    end

    test "wraps around 12 to 1" do
      assert Chef.camelot_compatible?("12A", "1A")
      assert Chef.camelot_compatible?("1B", "12B")
    end

    test "non-adjacent numbers are not compatible" do
      refute Chef.camelot_compatible?("1A", "3A")
      refute Chef.camelot_compatible?("5B", "8B")
    end

    test "adjacent numbers different column are not compatible" do
      refute Chef.camelot_compatible?("7A", "8B")
      refute Chef.camelot_compatible?("8B", "7A")
    end

    test "handles nil gracefully" do
      refute Chef.camelot_compatible?(nil, "8A")
      refute Chef.camelot_compatible?("8A", nil)
    end

    test "handles invalid codes" do
      refute Chef.camelot_compatible?("invalid", "8A")
      refute Chef.camelot_compatible?("13A", "1A")
    end

    test "all 12 positions self-compatible" do
      for n <- 1..12, col <- ["A", "B"] do
        code = "#{n}#{col}"
        assert Chef.camelot_compatible?(code, code), "#{code} should be self-compatible"
      end
    end
  end
end
