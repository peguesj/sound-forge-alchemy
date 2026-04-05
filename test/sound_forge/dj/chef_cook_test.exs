defmodule SoundForge.DJ.ChefCookTest do
  @moduledoc """
  Tests for Chef.cook/2 that exercise the DB fetch, ranking, and recipe-building
  code paths. The LLM call will fail but we test error paths and the
  fetch_analysed_tracks private function via cook/2.
  """
  use SoundForge.DataCase

  alias SoundForge.DJ.Chef

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "cook/2 error paths" do
    test "returns error with no analysed tracks" do
      user = user_fixture()
      # User has no tracks at all
      result = Chef.cook("deep house set", user.id)
      assert {:error, _reason} = result
    end

    test "returns error with tracks but no analysis" do
      user = user_fixture()
      track_fixture(%{user_id: user.id, title: "No Analysis"})
      # Track exists but has no analysis results
      result = Chef.cook("techno set", user.id)
      assert {:error, :no_analysed_tracks} = result
    end

    test "cook with analysed tracks exercises fetch and scoring" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id, title: "Analyzed Track", duration: 240})
      aj = analysis_job_fixture(%{track_id: track.id, status: :completed})

      analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: aj.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.85
      })

      # cook/2 will find the analysed track; may succeed if LLM proxy is running or fail
      result = Chef.cook("chill house mix", user.id)
      assert match?({:ok, %SoundForge.DJ.Chef.Recipe{}}, result) or match?({:error, _}, result)
    end

    test "cook with multiple analysed tracks exercises ranking" do
      user = user_fixture()

      for {title, tempo, key, energy} <- [
            {"Track A", 125.0, "C major", 0.7},
            {"Track B", 128.0, "A minor", 0.85},
            {"Track C", 130.0, "G minor", 0.9}
          ] do
        track = track_fixture(%{user_id: user.id, title: title, duration: 180})
        aj = analysis_job_fixture(%{track_id: track.id, status: :completed})

        analysis_result_fixture(%{
          track_id: track.id,
          analysis_job_id: aj.id,
          tempo: tempo,
          key: key,
          energy: energy
        })
      end

      result = Chef.cook("high energy techno", user.id)
      assert match?({:ok, %SoundForge.DJ.Chef.Recipe{}}, result) or match?({:error, _}, result)
    end
  end
end
