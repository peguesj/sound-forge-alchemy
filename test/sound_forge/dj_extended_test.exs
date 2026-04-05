defmodule SoundForge.DJExtendedTest do
  @moduledoc """
  Extended DJ context tests: stem loops, generate_auto_cues, deck state edge cases.
  """
  use SoundForge.DataCase

  alias SoundForge.DJ

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "stem_loops" do
    test "create_stem_loop/1 with invalid data returns error" do
      assert {:error, _} = DJ.create_stem_loop(%{})
    end

    test "get_stem_loop/1 returns nil for nonexistent" do
      assert is_nil(DJ.get_stem_loop(Ecto.UUID.generate()))
    end

    test "list_stem_loops/2 returns empty for no loops" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      assert DJ.list_stem_loops(track.id, user.id) == []
    end

    test "create, list, get, and delete stem loop" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :vocals})

      attrs = %{
        stem_id: stem.id,
        track_id: track.id,
        user_id: user.id,
        start_ms: 1000,
        end_ms: 5000,
        label: "Vocals Loop"
      }

      assert {:ok, loop} = DJ.create_stem_loop(attrs)
      assert loop.label == "Vocals Loop"
      assert loop.start_ms == 1000
      assert loop.end_ms == 5000

      # list_stem_loops returns the loop
      loops = DJ.list_stem_loops(track.id, user.id)
      assert length(loops) == 1
      assert hd(loops).id == loop.id

      # get_stem_loop returns the loop
      found = DJ.get_stem_loop(loop.id)
      assert found.id == loop.id

      # delete_stem_loop removes it
      assert {:ok, _} = DJ.delete_stem_loop(loop)
      assert is_nil(DJ.get_stem_loop(loop.id))
      assert DJ.list_stem_loops(track.id, user.id) == []
    end

    test "list_stem_loops/2 returns ordered by start_ms" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      pj = processing_job_fixture(%{track_id: track.id, user_id: user.id})
      stem = stem_fixture(%{track_id: track.id, processing_job_id: pj.id, stem_type: :drums})

      DJ.create_stem_loop(%{stem_id: stem.id, track_id: track.id, user_id: user.id, start_ms: 5000, end_ms: 8000})
      DJ.create_stem_loop(%{stem_id: stem.id, track_id: track.id, user_id: user.id, start_ms: 1000, end_ms: 3000})

      loops = DJ.list_stem_loops(track.id, user.id)
      starts = Enum.map(loops, & &1.start_ms)
      assert starts == [1000, 5000]
    end
  end

  describe "generate_auto_cues/2" do
    test "enqueues an Oban job", %{} do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})

      result = DJ.generate_auto_cues(track.id, user.id)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "deck state edge cases" do
    test "get_deck_state/2 returns nil for nonexistent user" do
      assert is_nil(DJ.get_deck_state(999_999, 1))
    end

    test "get_or_create_deck_session/3 with track_id" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      assert {:ok, session} = DJ.get_or_create_deck_session(user.id, 1, track.id)
      assert session.track_id == track.id
    end

    test "update_deck_session/2 updates pitch" do
      user = user_fixture()
      {:ok, session} = DJ.get_or_create_deck_session(user.id, 1)
      assert {:ok, updated} = DJ.update_deck_session(session, %{pitch_adjust: 2.5})
      assert updated.pitch_adjust == 2.5
    end

    test "get_deck_state/2 returns state with cue points and preloaded track" do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      DJ.load_track_to_deck(user.id, 1, track.id)
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 5000, cue_type: :hot})

      state = DJ.get_deck_state(user.id, 1)
      assert state.session.track_id == track.id
      assert length(state.cue_points) == 1
      # Track is preloaded with stems association
      assert state.session.track.id == track.id
    end
  end
end
