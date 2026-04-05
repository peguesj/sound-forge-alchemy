defmodule SoundForge.DJ.ChefTest do
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Chef

  describe "camelot_compatible?/2" do
    test "same code is compatible" do
      assert Chef.camelot_compatible?("8A", "8A")
      assert Chef.camelot_compatible?("1B", "1B")
    end

    test "same number different column is compatible (A<->B switch)" do
      assert Chef.camelot_compatible?("8A", "8B")
      assert Chef.camelot_compatible?("5B", "5A")
    end

    test "adjacent numbers same column are compatible" do
      assert Chef.camelot_compatible?("8A", "7A")
      assert Chef.camelot_compatible?("8A", "9A")
      assert Chef.camelot_compatible?("5B", "4B")
      assert Chef.camelot_compatible?("5B", "6B")
    end

    test "wrapping 12<->1 is compatible" do
      assert Chef.camelot_compatible?("12A", "1A")
      assert Chef.camelot_compatible?("1B", "12B")
    end

    test "non-adjacent numbers are incompatible" do
      refute Chef.camelot_compatible?("8A", "6A")
      refute Chef.camelot_compatible?("1B", "3B")
      refute Chef.camelot_compatible?("5A", "10A")
    end

    test "adjacent numbers different columns are incompatible" do
      refute Chef.camelot_compatible?("8A", "7B")
      refute Chef.camelot_compatible?("5B", "6A")
    end

    test "handles invalid camelot codes gracefully" do
      refute Chef.camelot_compatible?("invalid", "8A")
      refute Chef.camelot_compatible?("8A", "invalid")
      refute Chef.camelot_compatible?("", "")
    end

    test "handles nil inputs" do
      refute Chef.camelot_compatible?(nil, "8A")
      refute Chef.camelot_compatible?("8A", nil)
      refute Chef.camelot_compatible?(nil, nil)
    end

    test "all 12 positions wrap correctly" do
      # 11->12 adjacent
      assert Chef.camelot_compatible?("11A", "12A")
      # 12->1 wrapping
      assert Chef.camelot_compatible?("12A", "1A")
      # 1->2 adjacent
      assert Chef.camelot_compatible?("1A", "2A")
    end

    test "all 12 positions self-compatible for both columns" do
      for n <- 1..12, col <- ["A", "B"] do
        code = "#{n}#{col}"
        assert Chef.camelot_compatible?(code, code), "#{code} should be self-compatible"
      end
    end

    test "symmetry: if A is compatible with B, B is compatible with A" do
      pairs = [
        {"8A", "8B"},
        {"8A", "7A"},
        {"8A", "9A"},
        {"12A", "1A"},
        {"1B", "12B"}
      ]

      for {a, b} <- pairs do
        assert Chef.camelot_compatible?(a, b) == Chef.camelot_compatible?(b, a),
               "compatibility should be symmetric for #{a} and #{b}"
      end
    end

    test "2-step jumps are incompatible" do
      refute Chef.camelot_compatible?("1A", "3A")
      refute Chef.camelot_compatible?("6B", "8B")
      refute Chef.camelot_compatible?("10A", "12A")
    end

    test "diametrically opposite keys are incompatible" do
      refute Chef.camelot_compatible?("1A", "7A")
      refute Chef.camelot_compatible?("6B", "12B")
    end

    test "invalid column letter returns false" do
      refute Chef.camelot_compatible?("8C", "8A")
      refute Chef.camelot_compatible?("8D", "8B")
    end

    test "out-of-range numbers return false" do
      refute Chef.camelot_compatible?("13A", "1A")
      refute Chef.camelot_compatible?("100A", "1A")
    end
  end
end
