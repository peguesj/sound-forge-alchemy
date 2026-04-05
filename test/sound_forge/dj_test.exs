defmodule SoundForge.DJTest do
  use SoundForge.DataCase

  alias SoundForge.DJ

  import SoundForge.AccountsFixtures
  import SoundForge.MusicFixtures

  describe "cue_points" do
    setup do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      %{user: user, track: track}
    end

    test "create_cue_point/1 with valid data", %{user: user, track: track} do
      attrs = %{
        track_id: track.id,
        user_id: user.id,
        position_ms: 30_000,
        cue_type: :hot,
        label: "Drop",
        color: "#FF0000"
      }

      assert {:ok, cp} = DJ.create_cue_point(attrs)
      assert cp.position_ms == 30_000
      assert cp.cue_type == :hot
      assert cp.label == "Drop"
    end

    test "create_cue_point/1 with invalid data returns error" do
      assert {:error, _changeset} = DJ.create_cue_point(%{})
    end

    test "list_cue_points/2 returns ordered cue points", %{user: user, track: track} do
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 60_000, cue_type: :hot})
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 10_000, cue_type: :memory})
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 30_000, cue_type: :loop_in})

      cps = DJ.list_cue_points(track.id, user.id)
      assert length(cps) == 3
      positions = Enum.map(cps, & &1.position_ms)
      assert positions == [10_000, 30_000, 60_000]
    end

    test "list_cue_points/2 scopes to user", %{user: user, track: track} do
      other_user = user_fixture()
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 1000, cue_type: :hot})
      DJ.create_cue_point(%{track_id: track.id, user_id: other_user.id, position_ms: 2000, cue_type: :hot})

      assert length(DJ.list_cue_points(track.id, user.id)) == 1
      assert length(DJ.list_cue_points(track.id, other_user.id)) == 1
    end

    test "get_cue_point/1 returns cue point", %{user: user, track: track} do
      {:ok, cp} = DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 5000, cue_type: :hot})

      found = DJ.get_cue_point(cp.id)
      assert found.id == cp.id
    end

    test "get_cue_point/1 returns nil for nonexistent" do
      assert is_nil(DJ.get_cue_point(Ecto.UUID.generate()))
    end

    test "update_cue_point/2 updates attributes", %{user: user, track: track} do
      {:ok, cp} = DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 5000, cue_type: :hot})

      assert {:ok, updated} = DJ.update_cue_point(cp, %{label: "Build-up", position_ms: 6000})
      assert updated.label == "Build-up"
      assert updated.position_ms == 6000
    end

    test "delete_cue_point/1 removes cue point", %{user: user, track: track} do
      {:ok, cp} = DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 5000, cue_type: :hot})
      assert {:ok, _} = DJ.delete_cue_point(cp)
      assert is_nil(DJ.get_cue_point(cp.id))
    end
  end

  describe "auto cue points" do
    setup do
      user = user_fixture()
      track = track_fixture(%{user_id: user.id})
      %{user: user, track: track}
    end

    test "list_auto_cue_points/2 filters auto_generated", %{user: user, track: track} do
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 1000, cue_type: :hot, auto_generated: true})
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 2000, cue_type: :hot, auto_generated: false})

      auto = DJ.list_auto_cue_points(track.id, user.id)
      assert length(auto) == 1
      assert hd(auto).auto_generated == true
    end

    test "delete_auto_cue_points/2 removes only auto-generated", %{user: user, track: track} do
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 1000, cue_type: :hot, auto_generated: true})
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 2000, cue_type: :hot, auto_generated: true})
      DJ.create_cue_point(%{track_id: track.id, user_id: user.id, position_ms: 3000, cue_type: :memory, auto_generated: false})

      {count, _} = DJ.delete_auto_cue_points(track.id, user.id)
      assert count == 2

      remaining = DJ.list_cue_points(track.id, user.id)
      assert length(remaining) == 1
      assert hd(remaining).auto_generated == false
    end
  end

  describe "deck_sessions" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "get_or_create_deck_session/3 creates new session", %{user: user} do
      assert {:ok, session} = DJ.get_or_create_deck_session(user.id, 1)
      assert session.deck_number == 1
      assert session.user_id == user.id
    end

    test "get_or_create_deck_session/3 returns existing session", %{user: user} do
      {:ok, first} = DJ.get_or_create_deck_session(user.id, 1)
      {:ok, second} = DJ.get_or_create_deck_session(user.id, 1)
      assert first.id == second.id
    end

    test "get_or_create_deck_session/3 supports deck 2", %{user: user} do
      {:ok, d1} = DJ.get_or_create_deck_session(user.id, 1)
      {:ok, d2} = DJ.get_or_create_deck_session(user.id, 2)
      assert d1.id != d2.id
      assert d1.deck_number == 1
      assert d2.deck_number == 2
    end

    test "update_deck_session/2 updates tempo", %{user: user} do
      {:ok, session} = DJ.get_or_create_deck_session(user.id, 1)
      assert {:ok, updated} = DJ.update_deck_session(session, %{tempo_bpm: 128.0})
      assert updated.tempo_bpm == 128.0
    end

    test "load_track_to_deck/3 loads a track", %{user: user} do
      track = track_fixture(%{user_id: user.id})
      assert {:ok, session} = DJ.load_track_to_deck(user.id, 1, track.id)
      assert session.track_id == track.id
      assert session.track.id == track.id
    end

    test "get_deck_state/2 returns nil when no session", %{user: user} do
      assert is_nil(DJ.get_deck_state(user.id, 1))
    end

    test "get_deck_state/2 returns deck state with track", %{user: user} do
      track = track_fixture(%{user_id: user.id})
      DJ.load_track_to_deck(user.id, 1, track.id)

      state = DJ.get_deck_state(user.id, 1)
      assert state.session.deck_number == 1
      assert state.session.track.id == track.id
      assert is_list(state.cue_points)
    end
  end
end
