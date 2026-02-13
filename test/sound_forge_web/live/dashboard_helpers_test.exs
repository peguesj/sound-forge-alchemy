defmodule SoundForgeWeb.DashboardHelpersTest do
  use ExUnit.Case, async: true

  alias SoundForgeWeb.DashboardLive

  describe "normalize_spectral/2" do
    test "returns percentage for typical spectral centroid" do
      # 4000 Hz out of 8000 Hz max = 50%
      assert DashboardLive.normalize_spectral(4000, 8000) == 50.0
    end

    test "caps at 100%" do
      assert DashboardLive.normalize_spectral(10000, 8000) == 100
    end

    test "handles zero value" do
      assert DashboardLive.normalize_spectral(0, 8000) == 0.0
    end

    test "handles zero max_expected" do
      assert DashboardLive.normalize_spectral(100, 0) == 0
    end

    test "handles nil value" do
      assert DashboardLive.normalize_spectral(nil, 8000) == 0
    end

    test "normalizes spectral rolloff" do
      # 5512 Hz out of 11025 Hz max = 50%
      assert DashboardLive.normalize_spectral(5512.5, 11025) == 50.0
    end

    test "normalizes zero crossing rate" do
      # 0.1 out of 0.2 max = 50%
      assert DashboardLive.normalize_spectral(0.1, 0.2) == 50.0
    end
  end

  describe "pipeline_complete?/1" do
    test "returns true when analysis is completed" do
      pipeline = %{
        download: %{status: :completed, progress: 100},
        processing: %{status: :completed, progress: 100},
        analysis: %{status: :completed, progress: 100}
      }

      assert DashboardLive.pipeline_complete?(pipeline)
    end

    test "returns false when analysis is not completed" do
      pipeline = %{
        download: %{status: :completed, progress: 100},
        processing: %{status: :completed, progress: 100}
      }

      refute DashboardLive.pipeline_complete?(pipeline)
    end

    test "returns false for empty pipeline" do
      refute DashboardLive.pipeline_complete?(%{})
    end
  end
end
