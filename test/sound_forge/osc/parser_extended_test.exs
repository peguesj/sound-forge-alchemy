defmodule SoundForge.OSC.ParserExtendedTest do
  @moduledoc """
  Extended parser tests: encode/decode roundtrip, bundles, string args, blobs, edge cases.
  """
  use ExUnit.Case, async: true

  alias SoundForge.OSC.Parser

  describe "encode/2 and decode/1 roundtrip" do
    test "float argument roundtrip" do
      data = Parser.encode("/test", [1.5])
      assert {:ok, [msg]} = Parser.decode(data)
      assert msg.address == "/test"
      assert_in_delta hd(msg.args), 1.5, 0.001
    end

    test "integer argument roundtrip" do
      data = Parser.encode("/test", [42])
      assert {:ok, [msg]} = Parser.decode(data)
      assert msg.address == "/test"
      assert hd(msg.args) == 42
    end

    test "string argument roundtrip" do
      data = Parser.encode("/test", ["hello"])
      assert {:ok, [msg]} = Parser.decode(data)
      assert msg.address == "/test"
      assert hd(msg.args) == "hello"
    end

    test "multiple mixed arguments" do
      data = Parser.encode("/multi", [1.0, 42, "world"])
      assert {:ok, [msg]} = Parser.decode(data)
      assert msg.address == "/multi"
      assert length(msg.args) == 3
      [f, i, s] = msg.args
      assert_in_delta f, 1.0, 0.001
      assert i == 42
      assert s == "world"
    end

    test "no arguments" do
      data = Parser.encode("/empty")
      assert {:ok, [msg]} = Parser.decode(data)
      assert msg.address == "/empty"
      assert msg.args == []
    end

    test "negative integer" do
      data = Parser.encode("/neg", [-100])
      assert {:ok, [msg]} = Parser.decode(data)
      assert hd(msg.args) == -100
    end

    test "zero float" do
      data = Parser.encode("/zero", [0.0])
      assert {:ok, [msg]} = Parser.decode(data)
      assert_in_delta hd(msg.args), 0.0, 0.001
    end
  end

  describe "decode/1 bundles" do
    test "decodes OSC bundle" do
      # Build a bundle manually: #bundle\0 + 8-byte timetag + size-prefixed elements
      msg1 = Parser.encode("/one", [1])
      msg2 = Parser.encode("/two", [2])

      bundle =
        "#bundle\0" <>
          <<0::64>> <>
          <<byte_size(msg1)::32>> <>
          msg1 <>
          <<byte_size(msg2)::32>> <> msg2

      assert {:ok, messages} = Parser.decode(bundle)
      addresses = Enum.map(messages, & &1.address) |> Enum.sort()
      assert "/one" in addresses
      assert "/two" in addresses
    end
  end

  describe "decode/1 error handling" do
    test "returns error for empty binary" do
      result = Parser.decode(<<>>)
      assert match?({:error, _}, result)
    end

    test "returns error for invalid data" do
      result = Parser.decode(<<0xFF, 0xFF, 0xFF>>)
      assert match?({:error, _}, result)
    end
  end

  describe "encode/2 address padding" do
    test "address is 4-byte aligned" do
      data = Parser.encode("/a", [1])
      assert rem(byte_size(data), 4) == 0
    end

    test "long address is still aligned" do
      data = Parser.encode("/this/is/a/longer/address", [1.0])
      assert rem(byte_size(data), 4) == 0
    end
  end
end
