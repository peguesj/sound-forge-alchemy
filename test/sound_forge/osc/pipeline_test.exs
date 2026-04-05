defmodule SoundForge.OSC.PipelineTest do
  use ExUnit.Case, async: true

  alias SoundForge.OSC.Pipeline

  describe "simulate_osc/3" do
    test "sends UDP packet to specified port" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_osc("/test", [1.0], port: port)

      # Verify the packet arrived
      assert {:ok, {_, _, data}} = :gen_udp.recv(socket, 0, 1000)
      assert is_binary(data)

      :gen_udp.close(socket)
    end
  end

  describe "simulate_stem_volume/3" do
    test "sends stem volume message" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_stem_volume(1, 0.75, port: port)

      :gen_udp.close(socket)
    end
  end

  describe "simulate_transport/2" do
    test "sends transport action" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      for action <- [:play, :stop, :next, :prev] do
        assert :ok = Pipeline.simulate_transport(action, port: port)
      end

      :gen_udp.close(socket)
    end
  end

  describe "simulate_pad/3" do
    test "sends pad trigger" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      assert :ok = Pipeline.simulate_pad(5, 0.8, port: port)

      :gen_udp.close(socket)
    end
  end

  describe "benchmark/2" do
    test "returns stats map with all expected keys" do
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)

      result = Pipeline.benchmark(3, port: port, timeout: 100)

      assert is_map(result)
      assert result.total == 3
      assert Map.has_key?(result, :successes)
      assert Map.has_key?(result, :failures)
      assert Map.has_key?(result, :avg_latency_ms)
      assert Map.has_key?(result, :min_latency_ms)
      assert Map.has_key?(result, :max_latency_ms)
      assert Map.has_key?(result, :p99_latency_ms)

      :gen_udp.close(socket)
    end
  end
end
