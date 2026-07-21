defmodule SoundForge.MIDI.OutputTest do
  @moduledoc "Tests for MIDI.Output GenServer."
  use ExUnit.Case, async: true

  alias SoundForge.MIDI.Output

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Output)
    end

    test "start_link/1 is exported" do
      assert {:start_link, 1} in Output.__info__(:functions)
    end

    test "send/2 is exported" do
      assert {:send, 2} in Output.__info__(:functions)
    end

    test "send_sysex/2 is exported" do
      assert {:send_sysex, 2} in Output.__info__(:functions)
    end

    test "implements GenServer" do
      behaviours =
        Output.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert GenServer in behaviours
    end
  end

  describe "init/1" do
    test "starts with initial state" do
      {:ok, pid} = Output.start_link(name: :"output_test_#{:erlang.unique_integer([:positive])}")
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_call {:send, ...}" do
    setup do
      name = :"output_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Output.start_link(name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "rejects invalid message format", %{pid: pid} do
      result = GenServer.call(pid, {:send, "port:0", "not_a_map"})
      assert {:error, :invalid_message_format} = result
    end

    test "rejects unsupported message type", %{pid: pid} do
      result =
        GenServer.call(pid, {:send, "port:0", %{type: :unknown_type, channel: 0, data: []}})

      assert {:error, {:unsupported_message_type, :unknown_type}} = result
    end

    test "accepts valid note_on message (fails at connection)", %{pid: pid} do
      result =
        GenServer.call(
          pid,
          {:send, "port:0", %{type: :note_on, channel: 0, data: %{note: 60, velocity: 100}}}
        )

      # Will fail to connect to port but that exercises the send path
      assert result in [:ok, {:error, :connection_failed}]
    end

    test "accepts valid cc message (fails at connection)", %{pid: pid} do
      result =
        GenServer.call(
          pid,
          {:send, "port:0", %{type: :cc, channel: 0, data: %{controller: 1, value: 64}}}
        )

      assert result in [:ok, {:error, :connection_failed}]
    end

    test "accepts valid sysex message (fails at connection)", %{pid: pid} do
      result =
        GenServer.call(
          pid,
          {:send, "port:0", %{type: :sysex, channel: 0, data: [0xF0, 0x7E, 0xF7]}}
        )

      assert result in [:ok, {:error, :connection_failed}]
    end

    test "accepts valid program_change message", %{pid: pid} do
      result =
        GenServer.call(
          pid,
          {:send, "port:0", %{type: :program_change, channel: 0, data: %{program: 5}}}
        )

      assert result in [:ok, {:error, :connection_failed}]
    end

    test "accepts valid note_off message", %{pid: pid} do
      result =
        GenServer.call(
          pid,
          {:send, "port:0", %{type: :note_off, channel: 0, data: %{note: 60, velocity: 0}}}
        )

      assert result in [:ok, {:error, :connection_failed}]
    end
  end

  describe "handle_info" do
    setup do
      name = :"output_info_test_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Output.start_link(name: name)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{pid: pid}
    end

    test "handles :refill_tokens message", %{pid: pid} do
      send(pid, :refill_tokens)
      assert Process.alive?(pid)
    end

    test "handles unknown messages", %{pid: pid} do
      send(pid, {:random_message, :test})
      assert Process.alive?(pid)
    end

    test "handles :DOWN message", %{pid: pid} do
      send(pid, {:DOWN, make_ref(), :process, self(), :normal})
      assert Process.alive?(pid)
    end
  end
end
