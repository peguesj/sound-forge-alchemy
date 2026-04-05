defmodule SoundForge.DJ.ChefCamelotTest do
  @moduledoc "Tests for DJ.Chef Camelot compatibility functions."
  use ExUnit.Case, async: true

  alias SoundForge.DJ.Chef

  describe "camelot_compatible?/2" do
    test "same code is compatible" do
      assert Chef.camelot_compatible?("8A", "8A")
      assert Chef.camelot_compatible?("1B", "1B")
      assert Chef.camelot_compatible?("12A", "12A")
    end

    test "same number different column (A<->B) is compatible" do
      assert Chef.camelot_compatible?("8A", "8B")
      assert Chef.camelot_compatible?("1B", "1A")
      assert Chef.camelot_compatible?("12A", "12B")
    end

    test "adjacent numbers same column is compatible" do
      assert Chef.camelot_compatible?("5A", "6A")
      assert Chef.camelot_compatible?("6A", "5A")
      assert Chef.camelot_compatible?("8B", "9B")
      assert Chef.camelot_compatible?("9B", "8B")
    end

    test "wrapping 12->1 is compatible" do
      assert Chef.camelot_compatible?("12A", "1A")
      assert Chef.camelot_compatible?("1B", "12B")
    end

    test "non-adjacent numbers same column is not compatible" do
      refute Chef.camelot_compatible?("5A", "7A")
      refute Chef.camelot_compatible?("3B", "5B")
      refute Chef.camelot_compatible?("1A", "3A")
    end

    test "non-adjacent different column is not compatible" do
      refute Chef.camelot_compatible?("5A", "7B")
      refute Chef.camelot_compatible?("2A", "4B")
    end

    test "nil inputs return false" do
      refute Chef.camelot_compatible?(nil, "8A")
      refute Chef.camelot_compatible?("8A", nil)
      refute Chef.camelot_compatible?(nil, nil)
    end

    test "empty strings return false" do
      refute Chef.camelot_compatible?("", "8A")
      refute Chef.camelot_compatible?("8A", "")
    end

    test "invalid Camelot codes return false" do
      refute Chef.camelot_compatible?("XY", "1A")
      refute Chef.camelot_compatible?("abc", "1A")
      refute Chef.camelot_compatible?("1C", "1A")
    end

    test "all 12 positions with themselves are compatible" do
      for num <- 1..12, col <- ["A", "B"] do
        code = "#{num}#{col}"
        assert Chef.camelot_compatible?(code, code), "#{code} should be compatible with itself"
      end
    end

    test "adjacent pairs across the whole wheel" do
      for num <- 1..12, col <- ["A", "B"] do
        code = "#{num}#{col}"
        next_num = if num == 12, do: 1, else: num + 1
        next = "#{next_num}#{col}"
        assert Chef.camelot_compatible?(code, next), "#{code} should be compatible with #{next}"
      end
    end
  end
end
