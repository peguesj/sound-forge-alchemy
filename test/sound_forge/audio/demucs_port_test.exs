defmodule SoundForge.Audio.DemucsPortTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.DemucsPort

  describe "validate_model/1" do
    test "accepts valid models" do
      for model <- ~w(htdemucs htdemucs_ft htdemucs_6s mdx_extra) do
        assert :ok = DemucsPort.validate_model(model),
               "Expected #{model} to be valid"
      end
    end

    test "rejects invalid model" do
      assert {:error, {:invalid_model, "nonexistent"}} =
               DemucsPort.validate_model("nonexistent")
    end

    test "rejects empty string" do
      assert {:error, {:invalid_model, ""}} = DemucsPort.validate_model("")
    end
  end

  describe "valid_models/0" do
    test "returns expected model list" do
      models = DemucsPort.valid_models()
      assert is_list(models)
      assert "htdemucs" in models
      assert "htdemucs_ft" in models
      assert "htdemucs_6s" in models
      assert "mdx_extra" in models
    end
  end

  describe "start_link/1" do
    test "starts a GenServer without name" do
      assert {:ok, pid} = DemucsPort.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts a GenServer with name" do
      assert {:ok, pid} = DemucsPort.start_link(name: :test_demucs)
      assert Process.alive?(pid)
      assert Process.whereis(:test_demucs) == pid
      GenServer.stop(pid)
    end
  end

  describe "separate/2 validation" do
    test "rejects invalid model without starting a port" do
      assert {:error, {:invalid_model, "bad_model"}} =
               DemucsPort.separate("/some/path.mp3", model: "bad_model")
    end
  end
end
