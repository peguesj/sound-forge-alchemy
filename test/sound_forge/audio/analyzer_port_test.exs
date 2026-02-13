defmodule SoundForge.Audio.AnalyzerPortTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.AnalyzerPort

  describe "validate_features/1" do
    test "accepts valid features" do
      assert :ok = AnalyzerPort.validate_features(["tempo", "key", "energy"])
    end

    test "accepts 'all' feature" do
      assert :ok = AnalyzerPort.validate_features(["all"])
    end

    test "accepts all individual features" do
      for feature <- ~w(tempo key energy spectral mfcc chroma all) do
        assert :ok = AnalyzerPort.validate_features([feature]),
               "Expected #{feature} to be valid"
      end
    end

    test "rejects invalid features" do
      assert {:error, ["invalid_feature"]} =
               AnalyzerPort.validate_features(["tempo", "invalid_feature"])
    end

    test "returns all invalid features" do
      assert {:error, invalid} = AnalyzerPort.validate_features(["bad1", "bad2"])
      assert "bad1" in invalid
      assert "bad2" in invalid
    end

    test "accepts empty list" do
      assert :ok = AnalyzerPort.validate_features([])
    end
  end

  describe "valid_features/0" do
    test "returns expected feature list" do
      features = AnalyzerPort.valid_features()
      assert is_list(features)
      assert "tempo" in features
      assert "key" in features
      assert "energy" in features
      assert "spectral" in features
      assert "mfcc" in features
      assert "chroma" in features
      assert "all" in features
    end
  end

  describe "start_link/1" do
    test "starts a GenServer without name" do
      assert {:ok, pid} = AnalyzerPort.start_link()
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts a GenServer with name" do
      assert {:ok, pid} = AnalyzerPort.start_link(name: :test_analyzer)
      assert Process.alive?(pid)
      assert Process.whereis(:test_analyzer) == pid
      GenServer.stop(pid)
    end
  end

  describe "analyze/3 validation" do
    test "rejects invalid features without starting a port" do
      {:ok, pid} = AnalyzerPort.start_link()

      assert {:error, {:invalid_features, ["bogus"]}} =
               AnalyzerPort.analyze("/some/path.mp3", ["bogus"], server: pid)

      GenServer.stop(pid)
    end

    test "rejects mixed valid and invalid features" do
      {:ok, pid} = AnalyzerPort.start_link()

      assert {:error, {:invalid_features, ["nope"]}} =
               AnalyzerPort.analyze("/some/path.mp3", ["tempo", "nope"], server: pid)

      GenServer.stop(pid)
    end
  end
end
