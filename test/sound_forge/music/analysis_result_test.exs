defmodule SoundForge.Music.AnalysisResultTest do
  use ExUnit.Case, async: true

  alias SoundForge.Music.AnalysisResult

  @valid_attrs %{
    track_id: Ecto.UUID.generate(),
    analysis_job_id: Ecto.UUID.generate(),
    tempo: 128.0,
    key: "C minor",
    energy: 0.75,
    spectral_centroid: 2500.0,
    spectral_rolloff: 8000.0,
    zero_crossing_rate: 0.05,
    features: %{"chroma" => [0.1, 0.2, 0.3]}
  }

  describe "changeset/2" do
    test "valid attributes produce valid changeset" do
      changeset = AnalysisResult.changeset(%AnalysisResult{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires track_id" do
      changeset = AnalysisResult.changeset(%AnalysisResult{}, Map.delete(@valid_attrs, :track_id))
      refute changeset.valid?
    end

    test "requires analysis_job_id" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, Map.delete(@valid_attrs, :analysis_job_id))

      refute changeset.valid?
    end

    test "accepts partial analysis data" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          track_id: Ecto.UUID.generate(),
          analysis_job_id: Ecto.UUID.generate(),
          tempo: 120.0
        })

      assert changeset.valid?
    end

    test "accepts nil for all optional fields" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          track_id: Ecto.UUID.generate(),
          analysis_job_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "accepts features map with nested data" do
      changeset =
        AnalysisResult.changeset(%AnalysisResult{}, %{
          @valid_attrs
          | features: %{
              "chroma" => [0.1, 0.2],
              "mfcc" => [[1.0, 2.0], [3.0, 4.0]],
              "beats" => %{"positions" => [0.5, 1.0, 1.5]}
            }
        })

      assert changeset.valid?
    end
  end
end
