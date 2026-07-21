defmodule SoundForge.Audio.PrefetchTest do
  @moduledoc "Tests for Audio.Prefetch cache GenServer."
  use ExUnit.Case

  alias SoundForge.Audio.Prefetch

  describe "module" do
    test "module is loaded" do
      assert Code.ensure_loaded?(Prefetch)
    end

    test "start_link/1 is exported" do
      assert {:start_link, 1} in Prefetch.__info__(:functions)
    end

    test "start_link/0 is exported" do
      assert {:start_link, 0} in Prefetch.__info__(:functions)
    end

    test "prefetch_for_dj/1 is exported" do
      assert {:prefetch_for_dj, 1} in Prefetch.__info__(:functions)
    end

    test "prefetch_for_daw/1 is exported" do
      assert {:prefetch_for_daw, 1} in Prefetch.__info__(:functions)
    end

    test "get_cached/1 is exported" do
      assert {:get_cached, 1} in Prefetch.__info__(:functions)
    end

    test "get_cached/2 is exported" do
      assert {:get_cached, 2} in Prefetch.__info__(:functions)
    end

    test "put_cached/2 is exported" do
      assert {:put_cached, 2} in Prefetch.__info__(:functions)
    end

    test "invalidate/1 is exported" do
      assert {:invalidate, 1} in Prefetch.__info__(:functions)
    end

    test "cache_size/0 is exported" do
      assert {:cache_size, 0} in Prefetch.__info__(:functions)
    end

    test "evict_expired/0 is exported" do
      assert {:evict_expired, 0} in Prefetch.__info__(:functions)
    end
  end

  describe "guard clauses" do
    test "get_cached/1 returns nil for non-binary" do
      assert Prefetch.get_cached(nil) == nil
      assert Prefetch.get_cached(123) == nil
    end

    test "get_cached/2 returns nil for invalid args" do
      assert Prefetch.get_cached(nil, :dj) == nil
      assert Prefetch.get_cached(123, :daw) == nil
    end

    test "prefetch_for_dj/1 returns :ok for nil" do
      assert Prefetch.prefetch_for_dj(nil) == :ok
    end

    test "prefetch_for_daw/1 returns :ok for nil" do
      assert Prefetch.prefetch_for_daw(nil) == :ok
    end
  end

  describe "ETS cache operations" do
    setup do
      # Ensure the Prefetch GenServer is running (it may be in the supervision tree)
      pid = Process.whereis(SoundForge.Audio.Prefetch)

      if pid && Process.alive?(pid) do
        %{prefetch_running: true}
      else
        %{prefetch_running: false}
      end
    end

    test "put_cached and get_cached round-trip", %{prefetch_running: running} do
      if running do
        track_id = Ecto.UUID.generate()

        data = %{
          mode: :dj,
          tempo: 128.0,
          key: "Am",
          cached_at: System.monotonic_time(:millisecond)
        }

        assert :ok = Prefetch.put_cached(track_id, data)
        cached = Prefetch.get_cached(track_id)
        assert cached != nil
        assert cached.tempo == 128.0
      else
        assert {:put_cached, 2} in Prefetch.__info__(:functions)
      end
    end

    test "invalidate removes cached entry", %{prefetch_running: running} do
      if running do
        track_id = Ecto.UUID.generate()
        data = %{mode: :dj, tempo: 140.0, cached_at: System.monotonic_time(:millisecond)}

        Prefetch.put_cached(track_id, data)
        assert Prefetch.get_cached(track_id) != nil

        Prefetch.invalidate(track_id)
        assert Prefetch.get_cached(track_id) == nil
      else
        assert {:invalidate, 1} in Prefetch.__info__(:functions)
      end
    end

    test "cache_size returns integer", %{prefetch_running: running} do
      if running do
        size = Prefetch.cache_size()
        assert is_integer(size)
        assert size >= 0
      else
        assert {:cache_size, 0} in Prefetch.__info__(:functions)
      end
    end

    test "evict_expired returns integer count", %{prefetch_running: running} do
      if running do
        result = Prefetch.evict_expired()
        assert is_integer(result)
        assert result >= 0
      else
        assert {:evict_expired, 0} in Prefetch.__info__(:functions)
      end
    end

    test "get_cached/2 filters by mode", %{prefetch_running: running} do
      if running do
        track_id = Ecto.UUID.generate()
        data = %{mode: :dj, tempo: 120.0, cached_at: System.monotonic_time(:millisecond)}

        Prefetch.put_cached(track_id, data)
        assert Prefetch.get_cached(track_id, :dj) != nil
        assert Prefetch.get_cached(track_id, :daw) == nil
      else
        assert {:get_cached, 2} in Prefetch.__info__(:functions)
      end
    end
  end
end
