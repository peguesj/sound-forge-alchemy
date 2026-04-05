defmodule SoundForge.Jobs.ChefWorkerTest do
  use SoundForge.DataCase

  alias SoundForge.Jobs.ChefWorker

  describe "worker configuration" do
    test "uses processing queue" do
      changeset = ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.queue == "processing"
    end

    test "has max_attempts of 3" do
      changeset = ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.max_attempts == 3
    end

    test "has priority 3" do
      changeset = ChefWorker.new(%{"user_id" => 1})
      assert changeset.changes.priority == 3
    end
  end

  describe "new/1" do
    test "creates valid job with required args" do
      args = %{
        "user_id" => 1,
        "track_ids" => [Ecto.UUID.generate(), Ecto.UUID.generate()],
        "stem_types" => ["vocals", "drums", "bass", "other"],
        "cue_plan" => [],
        "candidate_track_ids" => [Ecto.UUID.generate()],
        "recipe_meta" => %{"prompt" => "deep house set"}
      }

      changeset = ChefWorker.new(args)
      assert changeset.valid?
    end

    test "job args include all required fields" do
      track_ids = [Ecto.UUID.generate()]

      args = %{
        "user_id" => 42,
        "track_ids" => track_ids,
        "stem_types" => ["vocals"],
        "cue_plan" => [%{"track_id" => hd(track_ids), "position_ms" => 0, "label" => "Start"}],
        "candidate_track_ids" => [],
        "recipe_meta" => %{"energy_curve" => "ascending"}
      }

      changeset = ChefWorker.new(args)
      assert changeset.valid?
      assert changeset.changes.args["user_id"] == 42
    end
  end
end
