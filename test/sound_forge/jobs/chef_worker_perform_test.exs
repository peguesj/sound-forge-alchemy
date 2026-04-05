defmodule SoundForge.Jobs.ChefWorkerPerformTest do
  @moduledoc "Tests for ChefWorker perform/1 code paths."
  use SoundForge.DataCase

  alias SoundForge.Jobs.ChefWorker

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "perform/1" do
    test "returns error when all tracks fail processing" do
      user = user_fixture()
      # Track exists but has no stems or download - will fail at processing
      track = track_fixture(%{user_id: user.id})

      oban_job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "track_ids" => [track.id],
          "stem_types" => ["vocals", "drums"],
          "cue_plan" => [],
          "candidate_track_ids" => [],
          "recipe_meta" => %{"prompt" => "test recipe"}
        },
        attempt: 1
      }

      result = ChefWorker.perform(oban_job)
      assert {:error, _reason} = result
    end

    test "handles empty track_ids gracefully" do
      user = user_fixture()

      oban_job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "track_ids" => [],
          "stem_types" => ["vocals"],
          "cue_plan" => [],
          "candidate_track_ids" => [],
          "recipe_meta" => %{}
        },
        attempt: 1
      }

      result = ChefWorker.perform(oban_job)
      # Empty tracks = no finalized tracks = failure
      assert {:error, _} = result
    end

    test "exercises substitution logic when candidate_track_ids provided" do
      user = user_fixture()
      track1 = track_fixture(%{user_id: user.id})
      track2 = track_fixture(%{user_id: user.id})

      oban_job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "track_ids" => [track1.id],
          "stem_types" => ["vocals"],
          "cue_plan" => [],
          "candidate_track_ids" => [track2.id],
          "recipe_meta" => %{"energy_curve" => "flat"}
        },
        attempt: 1
      }

      result = ChefWorker.perform(oban_job)
      # Both tracks will fail (no audio), but code paths for substitution are exercised
      assert {:error, _} = result
    end
  end
end
