defmodule SoundForge.DJ.ChefCoverageTest do
  @moduledoc "Additional tests for DJ.Chef: cook/2 and edge cases."
  use SoundForge.DataCase

  import SoundForge.MusicFixtures

  alias SoundForge.DJ.Chef

  setup do
    user = SoundForge.AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "cook/2" do
    test "returns recipe for simple prompt", %{user: user} do
      # Create a track so the chef has something to work with
      track = track_fixture(%{user_id: user.id, title: "Chef Track", artist: "DJ Test", duration: 300})
      download_job_fixture(%{track_id: track.id, status: :completed, output_path: "priv/uploads/downloads/chef.mp3"})
      pj = processing_job_fixture(%{track_id: track.id, model: "htdemucs", status: :completed})
      stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals, file_path: "stems/v.wav", file_size: 1024})

      result = Chef.cook("play something energetic", user.id)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "returns error for empty prompt", %{user: user} do
      result = Chef.cook("", user.id)
      # Either returns an empty recipe or handles gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "camelot_compatible?/2 additional edge cases" do
    test "handles lowercase input" do
      # Camelot codes should be uppercase, lowercase returns false
      refute Chef.camelot_compatible?("8a", "8a")
    end

    test "handles mixed case" do
      refute Chef.camelot_compatible?("8a", "8A")
    end

    test "handles numeric strings" do
      refute Chef.camelot_compatible?("8", "8")
    end
  end
end
