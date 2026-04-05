defmodule SoundForge.Integrations.Melodics.MelodicsSessionTest do
  @moduledoc "Tests for MelodicsSession changeset validation."
  use SoundForge.DataCase

  alias SoundForge.Integrations.Melodics.MelodicsSession

  describe "changeset/2" do
    test "valid changeset with all fields" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Funk Basics",
          user_id: user.id,
          accuracy: 85.5,
          bpm: 120,
          instrument: "keys",
          practiced_at: ~U[2026-03-01 12:00:00Z]
        })

      assert cs.valid?
    end

    test "valid changeset with only required fields" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Drum Intro",
          user_id: user.id
        })

      assert cs.valid?
    end

    test "invalid without lesson_name" do
      user = SoundForge.AccountsFixtures.user_fixture()
      cs = MelodicsSession.changeset(%MelodicsSession{}, %{user_id: user.id})
      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:lesson_name)
    end

    test "invalid without user_id" do
      cs = MelodicsSession.changeset(%MelodicsSession{}, %{lesson_name: "Test"})
      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:user_id)
    end

    test "invalid with negative accuracy" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Test",
          user_id: user.id,
          accuracy: -1.0
        })

      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:accuracy)
    end

    test "invalid with accuracy over 100" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Test",
          user_id: user.id,
          accuracy: 101.0
        })

      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:accuracy)
    end

    test "invalid with zero bpm" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Test",
          user_id: user.id,
          bpm: 0
        })

      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:bpm)
    end

    test "invalid with negative bpm" do
      user = SoundForge.AccountsFixtures.user_fixture()

      cs =
        MelodicsSession.changeset(%MelodicsSession{}, %{
          lesson_name: "Test",
          user_id: user.id,
          bpm: -10
        })

      refute cs.valid?
      assert errors_on(cs) |> Map.has_key?(:bpm)
    end

    test "valid at boundary accuracy values" do
      user = SoundForge.AccountsFixtures.user_fixture()

      for acc <- [0.0, 50.0, 100.0] do
        cs =
          MelodicsSession.changeset(%MelodicsSession{}, %{
            lesson_name: "Boundary",
            user_id: user.id,
            accuracy: acc
          })

        assert cs.valid?, "Expected valid for accuracy=#{acc}"
      end
    end
  end
end
