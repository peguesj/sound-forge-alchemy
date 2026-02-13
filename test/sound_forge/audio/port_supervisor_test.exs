defmodule SoundForge.Audio.PortSupervisorTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.PortSupervisor

  test "can start demucs port processes dynamically" do
    {:ok, pid} = PortSupervisor.start_demucs()
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "can start analyzer port processes dynamically" do
    {:ok, pid} = PortSupervisor.start_analyzer()
    assert Process.alive?(pid)
    GenServer.stop(pid)
  end

  test "can start multiple port processes concurrently" do
    {:ok, pid1} = PortSupervisor.start_demucs()
    {:ok, pid2} = PortSupervisor.start_demucs()
    {:ok, pid3} = PortSupervisor.start_analyzer()

    assert pid1 != pid2
    assert pid2 != pid3
    assert Process.alive?(pid1)
    assert Process.alive?(pid2)
    assert Process.alive?(pid3)

    GenServer.stop(pid1)
    GenServer.stop(pid2)
    GenServer.stop(pid3)
  end
end
