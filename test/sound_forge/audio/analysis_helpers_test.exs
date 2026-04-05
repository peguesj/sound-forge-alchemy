defmodule SoundForge.Audio.AnalysisHelpersTest do
  use ExUnit.Case, async: true

  alias SoundForge.Audio.AnalysisHelpers

  @sample_features %{
    "structure" => %{
      "segments" => [
        %{"label" => "intro", "start" => 0.0, "end" => 15.0},
        %{"label" => "verse", "start" => 15.0, "end" => 45.0}
      ],
      "bar_times" => [0.0, 2.0, 4.0, 6.0],
      "time_signature" => %{"beats_per_bar" => 4, "confidence" => 0.95}
    },
    "loop_points" => %{
      "recommended" => [
        %{"start" => 15.0, "end" => 31.0, "confidence" => 0.9}
      ],
      "all" => [
        %{"start" => 15.0, "end" => 31.0},
        %{"start" => 45.0, "end" => 61.0}
      ]
    },
    "arrangement_markers" => [
      %{"time" => 0.0, "label" => "intro"},
      %{"time" => 45.0, "label" => "chorus"}
    ],
    "energy_curve" => %{
      "values" => [0.1, 0.3, 0.5, 0.8, 0.9],
      "times" => [0.0, 15.0, 30.0, 45.0, 60.0]
    }
  }

  describe "structure_segments/1" do
    test "extracts segments from valid features" do
      result = AnalysisHelpers.structure_segments(%{features: @sample_features})
      assert length(result) == 2
      assert hd(result)["label"] == "intro"
    end

    test "returns [] for nil input" do
      assert AnalysisHelpers.structure_segments(nil) == []
    end

    test "returns [] for nil features" do
      assert AnalysisHelpers.structure_segments(%{features: nil}) == []
    end

    test "returns [] when structure key missing" do
      assert AnalysisHelpers.structure_segments(%{features: %{}}) == []
    end
  end

  describe "recommended_loop_points/1" do
    test "extracts recommended loop points" do
      result = AnalysisHelpers.recommended_loop_points(%{features: @sample_features})
      assert length(result) == 1
      assert hd(result)["confidence"] == 0.9
    end

    test "returns [] for nil" do
      assert AnalysisHelpers.recommended_loop_points(nil) == []
    end

    test "returns [] for nil features" do
      assert AnalysisHelpers.recommended_loop_points(%{features: nil}) == []
    end
  end

  describe "all_loop_points/1" do
    test "extracts all loop points" do
      result = AnalysisHelpers.all_loop_points(%{features: @sample_features})
      assert length(result) == 2
    end

    test "returns [] for nil" do
      assert AnalysisHelpers.all_loop_points(nil) == []
    end

    test "returns [] for nil features" do
      assert AnalysisHelpers.all_loop_points(%{features: nil}) == []
    end
  end

  describe "arrangement_markers/1" do
    test "extracts markers from features" do
      result = AnalysisHelpers.arrangement_markers(%{features: @sample_features})
      assert length(result) == 2
      assert hd(result)["label"] == "intro"
    end

    test "returns [] for nil" do
      assert AnalysisHelpers.arrangement_markers(nil) == []
    end

    test "returns [] for nil features" do
      assert AnalysisHelpers.arrangement_markers(%{features: nil}) == []
    end

    test "returns [] when key missing" do
      assert AnalysisHelpers.arrangement_markers(%{features: %{}}) == []
    end
  end

  describe "energy_curve/1" do
    test "extracts energy curve" do
      result = AnalysisHelpers.energy_curve(%{features: @sample_features})
      assert is_map(result)
      assert length(result["values"]) == 5
    end

    test "returns %{} for nil" do
      assert AnalysisHelpers.energy_curve(nil) == %{}
    end

    test "returns %{} for nil features" do
      assert AnalysisHelpers.energy_curve(%{features: nil}) == %{}
    end
  end

  describe "bar_times/1" do
    test "extracts bar times" do
      result = AnalysisHelpers.bar_times(%{features: @sample_features})
      assert result == [0.0, 2.0, 4.0, 6.0]
    end

    test "returns [] for nil" do
      assert AnalysisHelpers.bar_times(nil) == []
    end

    test "returns [] for nil features" do
      assert AnalysisHelpers.bar_times(%{features: nil}) == []
    end
  end

  describe "time_signature/1" do
    test "extracts time signature" do
      result = AnalysisHelpers.time_signature(%{features: @sample_features})
      assert result["beats_per_bar"] == 4
      assert result["confidence"] == 0.95
    end

    test "returns default for nil" do
      result = AnalysisHelpers.time_signature(nil)
      assert result == %{"beats_per_bar" => 4, "confidence" => 0.0}
    end

    test "returns default for nil features" do
      result = AnalysisHelpers.time_signature(%{features: nil})
      assert result == %{"beats_per_bar" => 4, "confidence" => 0.0}
    end

    test "returns default when key missing" do
      result = AnalysisHelpers.time_signature(%{features: %{}})
      assert result == %{"beats_per_bar" => 4, "confidence" => 0.0}
    end
  end
end
