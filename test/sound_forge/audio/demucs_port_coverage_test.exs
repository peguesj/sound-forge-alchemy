defmodule SoundForge.Audio.DemucsPortCoverageTest do
  @moduledoc "Tests for DemucsPort: validate_model and valid_models."
  use ExUnit.Case, async: true

  alias SoundForge.Audio.DemucsPort

  describe "validate_model/1" do
    test "valid model htdemucs" do
      assert :ok = DemucsPort.validate_model("htdemucs")
    end

    test "valid model htdemucs_ft" do
      assert :ok = DemucsPort.validate_model("htdemucs_ft")
    end

    test "valid model htdemucs_6s" do
      assert :ok = DemucsPort.validate_model("htdemucs_6s")
    end

    test "valid model mdx_extra" do
      assert :ok = DemucsPort.validate_model("mdx_extra")
    end

    test "invalid model returns error" do
      assert {:error, {:invalid_model, "bad_model"}} = DemucsPort.validate_model("bad_model")
    end

    test "empty string is invalid" do
      assert {:error, {:invalid_model, ""}} = DemucsPort.validate_model("")
    end
  end

  describe "valid_models/0" do
    test "returns list of 4 models" do
      models = DemucsPort.valid_models()
      assert length(models) == 4
    end

    test "includes htdemucs" do
      assert "htdemucs" in DemucsPort.valid_models()
    end

    test "all entries are strings" do
      assert Enum.all?(DemucsPort.valid_models(), &is_binary/1)
    end
  end

  describe "start_link/1" do
    test "starts without name" do
      assert {:ok, pid} = DemucsPort.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom name" do
      name = :"demucs_test_#{System.unique_integer([:positive])}"
      assert {:ok, pid} = DemucsPort.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
