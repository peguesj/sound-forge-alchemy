defmodule SoundForge.MIDI.DispatcherTest do
  @moduledoc """
  Tests for MIDI Dispatcher public API.
  Note: Full integration tests require Midiex/MIDI hardware,
  so we test the pure functions and module structure.
  """
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Dispatcher

  describe "topic/1" do
    test "returns correct PubSub topic format" do
      assert Dispatcher.topic("input:0") == "midi:messages:input:0"
    end

    test "handles integer port_id" do
      assert Dispatcher.topic("5") == "midi:messages:5"
    end

    test "handles composite port_id" do
      assert Dispatcher.topic("input:3") == "midi:messages:input:3"
    end
  end

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Dispatcher)
    end

    test "subscribe/1 is exported" do
      assert {:subscribe, 1} in Dispatcher.__info__(:functions)
    end

    test "topic/1 is exported" do
      assert {:topic, 1} in Dispatcher.__info__(:functions)
    end

    test "start_link/1 is exported" do
      assert {:start_link, 1} in Dispatcher.__info__(:functions)
    end
  end
end
