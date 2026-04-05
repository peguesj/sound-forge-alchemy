defmodule SoundForge.OSC.ParserTest do
  use ExUnit.Case, async: true

  alias SoundForge.OSC.Parser

  describe "encode/2" do
    test "encodes simple address with no args" do
      result = Parser.encode("/test")
      assert is_binary(result)
      assert String.starts_with?(result, "/test")
    end

    test "encodes address with float arg" do
      result = Parser.encode("/volume", [0.5])
      assert is_binary(result)
    end

    test "encodes address with integer arg" do
      result = Parser.encode("/pad", [42])
      assert is_binary(result)
    end

    test "encodes address with string arg" do
      result = Parser.encode("/name", ["hello"])
      assert is_binary(result)
    end

    test "encodes address with multiple args" do
      result = Parser.encode("/multi", [1.0, 42, "test"])
      assert is_binary(result)
    end
  end

  describe "decode/1" do
    test "round-trips simple address" do
      encoded = Parser.encode("/test")
      assert {:ok, [%{address: "/test", args: []}]} = Parser.decode(encoded)
    end

    test "round-trips float arg" do
      encoded = Parser.encode("/vol", [1.0])
      {:ok, [msg]} = Parser.decode(encoded)
      assert msg.address == "/vol"
      assert length(msg.args) == 1
      [val] = msg.args
      assert_in_delta val, 1.0, 0.001
    end

    test "round-trips integer arg" do
      encoded = Parser.encode("/pad", [42])
      assert {:ok, [%{address: "/pad", args: [42]}]} = Parser.decode(encoded)
    end

    test "round-trips string arg" do
      encoded = Parser.encode("/name", ["hello"])
      assert {:ok, [%{address: "/name", args: ["hello"]}]} = Parser.decode(encoded)
    end

    test "round-trips multiple args" do
      encoded = Parser.encode("/multi", [42, 3.14])
      {:ok, [msg]} = Parser.decode(encoded)
      assert msg.address == "/multi"
      assert length(msg.args) == 2
      [int_val, float_val] = msg.args
      assert int_val == 42
      assert_in_delta float_val, 3.14, 0.01
    end

    test "handles minimal binary gracefully" do
      # Even minimal data parses to an empty-address message
      result = Parser.decode(<<0, 0, 0>>)
      assert {:ok, _} = result
    end
  end

  describe "encode/decode stem addresses" do
    test "stem volume address" do
      encoded = Parser.encode("/stem/1/volume", [0.75])
      {:ok, [msg]} = Parser.decode(encoded)
      assert msg.address == "/stem/1/volume"
      assert_in_delta hd(msg.args), 0.75, 0.001
    end

    test "transport address" do
      encoded = Parser.encode("/transport/play", [1.0])
      {:ok, [msg]} = Parser.decode(encoded)
      assert msg.address == "/transport/play"
    end

    test "pad address" do
      encoded = Parser.encode("/pad/5", [1.0])
      {:ok, [msg]} = Parser.decode(encoded)
      assert msg.address == "/pad/5"
    end
  end
end
