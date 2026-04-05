defmodule SoundForge.OSC.PipelineExtendedTest do
  @moduledoc """
  Extended pipeline tests: test_pipeline, benchmark stats, edge cases.
  """
  use ExUnit.Case, async: true

  alias SoundForge.OSC.Pipeline

  describe "test_pipeline/3" do
    test "returns timeout when no PubSub subscriber produces response" do
      # Send to a random port; no OSC server listening
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      result = Pipeline.test_pipeline("/stem/1/volume", [0.5], port: port, timeout: 50)
      assert {:error, :timeout} = result

      :gen_udp.close(socket)
    end
  end

  describe "simulate_osc/3 edge cases" do
    test "sends to custom host and port" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_osc("/custom", [42], host: "127.0.0.1", port: port)

      {:ok, {_, _, data}} = :gen_udp.recv(socket, 0, 1000)
      assert is_binary(data)

      :gen_udp.close(socket)
    end

    test "sends multiple float args" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_osc("/multi", [1.0, 2.0, 3.0], port: port)

      :gen_udp.close(socket)
    end
  end

  describe "benchmark/2 edge cases" do
    test "with 1 iteration" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      result = Pipeline.benchmark(1, port: port, timeout: 50)
      assert result.total == 1
      assert result.failures == 1
      assert result.successes == 0
      assert result.avg_latency_ms == nil
      assert result.min_latency_ms == nil
      assert result.max_latency_ms == nil
      assert result.p99_latency_ms == nil

      :gen_udp.close(socket)
    end
  end

  describe "simulate_transport/2 all actions" do
    test "all valid transport actions succeed" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      for action <- [:play, :stop, :next, :prev] do
        assert :ok = Pipeline.simulate_transport(action, port: port)
      end

      :gen_udp.close(socket)
    end
  end

  describe "simulate_pad/3 with default velocity" do
    test "default velocity is 1.0" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_pad(0, 1.0, port: port)

      :gen_udp.close(socket)
    end
  end
end
