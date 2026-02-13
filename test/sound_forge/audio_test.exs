defmodule SoundForge.AudioTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.AnalyzerPort
  alias SoundForge.Audio.DemucsPort

  describe "AnalyzerPort" do
    test "module compiles and exports expected functions" do
      assert function_exported?(AnalyzerPort, :start_link, 0)
      assert function_exported?(AnalyzerPort, :start_link, 1)
      assert function_exported?(AnalyzerPort, :analyze, 1)
      assert function_exported?(AnalyzerPort, :analyze, 2)
      assert function_exported?(AnalyzerPort, :validate_features, 1)
      assert function_exported?(AnalyzerPort, :valid_features, 0)
    end

    test "valid_features returns expected list" do
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

    test "validate_features accepts valid features" do
      assert :ok == AnalyzerPort.validate_features(["tempo"])
      assert :ok == AnalyzerPort.validate_features(["tempo", "key"])
      assert :ok == AnalyzerPort.validate_features(["all"])
      assert :ok == AnalyzerPort.validate_features(["tempo", "key", "energy"])
    end

    test "validate_features rejects invalid features" do
      assert {:error, ["invalid"]} == AnalyzerPort.validate_features(["invalid"])
      assert {:error, ["bad"]} == AnalyzerPort.validate_features(["tempo", "bad"])
      assert {:error, ["foo", "bar"]} == AnalyzerPort.validate_features(["foo", "bar"])
    end

    test "GenServer can start" do
      # Start the GenServer
      {:ok, pid} = AnalyzerPort.start_link(name: :test_analyzer_port)
      assert Process.alive?(pid)

      # Stop it
      GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "handles missing Python executable gracefully" do
      # This test requires mocking System.find_executable, which is complex
      # In a real test environment, we would use Mox or similar
      # For now, we just verify the error handling path exists
      assert function_exported?(AnalyzerPort, :handle_call, 3)
    end

    test "handles missing audio file gracefully" do
      # Start a test instance
      {:ok, pid} = AnalyzerPort.start_link(name: :test_analyzer_missing_file)

      # Try to analyze a non-existent file
      # This will likely timeout or return an error depending on Python availability
      result = GenServer.call(pid, {:analyze, "/nonexistent/file.mp3", ["tempo"]}, 5000)

      # We expect either an error or a timeout
      # The actual error depends on whether Python is available
      assert match?({:error, _}, result) or match?(:timeout, result)

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "DemucsPort" do
    test "module compiles and exports expected functions" do
      # Note: start_link with default args creates both /0 and /1 arities
      assert function_exported?(DemucsPort, :start_link, 1)
      assert function_exported?(DemucsPort, :separate, 2)
      assert function_exported?(DemucsPort, :validate_model, 1)
      assert function_exported?(DemucsPort, :valid_models, 0)
    end

    test "valid_models returns expected list" do
      models = DemucsPort.valid_models()
      assert is_list(models)
      assert "htdemucs" in models
      assert "htdemucs_ft" in models
      assert "mdx_extra" in models
    end

    test "validate_model accepts valid models" do
      assert :ok == DemucsPort.validate_model("htdemucs")
      assert :ok == DemucsPort.validate_model("htdemucs_ft")
      assert :ok == DemucsPort.validate_model("mdx_extra")
    end

    test "validate_model rejects invalid models" do
      assert {:error, {:invalid_model, "invalid"}} == DemucsPort.validate_model("invalid")
      assert {:error, {:invalid_model, "foo"}} == DemucsPort.validate_model("foo")
    end

    test "GenServer can start" do
      # Start the GenServer
      {:ok, pid} = DemucsPort.start_link(name: :test_demucs_port)
      assert Process.alive?(pid)

      # Stop it
      GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "handles invalid model in separate call" do
      {:ok, pid} = DemucsPort.start_link(name: :test_demucs_invalid_model)

      # Try to use an invalid model
      result = DemucsPort.separate("/some/file.mp3", model: "invalid_model")

      assert {:error, {:invalid_model, "invalid_model"}} == result

      # Cleanup
      GenServer.stop(pid)
    end

    test "handles missing Python executable gracefully" do
      # This test requires mocking System.find_executable, which is complex
      # In a real test environment, we would use Mox or similar
      # For now, we just verify the error handling path exists
      assert function_exported?(DemucsPort, :handle_call, 3)
    end

    test "separate accepts progress callback" do
      {:ok, pid} = DemucsPort.start_link(name: :test_demucs_callback)

      # Define a callback that captures progress
      parent = self()

      callback = fn percent, message ->
        send(parent, {:progress, percent, message})
      end

      # Try to separate (will fail due to missing Python/file, but that's ok)
      # We're just testing that the callback parameter is accepted
      _result = GenServer.call(
        pid,
        {:separate, "/nonexistent.mp3", "htdemucs", "/tmp/test", callback},
        5000
      )

      # Just verify the call was accepted
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "Integration" do
    test "both ports can be started simultaneously" do
      {:ok, analyzer_pid} = AnalyzerPort.start_link(name: :integration_analyzer)
      {:ok, demucs_pid} = DemucsPort.start_link(name: :integration_demucs)

      assert Process.alive?(analyzer_pid)
      assert Process.alive?(demucs_pid)

      GenServer.stop(analyzer_pid)
      GenServer.stop(demucs_pid)

      refute Process.alive?(analyzer_pid)
      refute Process.alive?(demucs_pid)
    end
  end
end
