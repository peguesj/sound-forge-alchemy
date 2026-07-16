defmodule SoundForge.LiveHarness.ReporterTest do
  use ExUnit.Case, async: true

  alias SoundForge.LiveHarness.Reporter

  defp results do
    [
      %{
        id: "s1",
        criterion: "S0",
        title: "one",
        kind: :api,
        status: :pass,
        message: "ok",
        evidence: "live",
        url: "http://localhost:4000/health",
        final_path: "/health"
      },
      %{
        id: "s2",
        criterion: "S1",
        title: "two",
        kind: :route,
        status: :fail,
        message: "boom",
        evidence: "crash",
        url: nil,
        final_path: nil
      }
    ]
  end

  describe "run_id/0" do
    test "is filesystem-safe" do
      id = Reporter.run_id()
      refute id =~ ":"
      refute id =~ "."
    end
  end

  describe "write_summary/3" do
    @tag :tmp_dir
    test "writes decodable summary JSON with totals", %{tmp_dir: tmp} do
      assert {:ok, %{path: path, summary: summary}} =
               Reporter.write_summary("run-1", results(),
                 root: tmp,
                 base_url: "http://localhost:4000"
               )

      assert path ==
               Path.join([tmp, "test-results", "live-harness", "run-1", "summary.json"])

      assert summary.totals.total == 2
      assert summary.totals.fail == 1

      decoded = path |> File.read!() |> Jason.decode!()
      assert decoded["run_id"] == "run-1"
      assert decoded["base_url"] == "http://localhost:4000"
      assert length(decoded["results"]) == 2
    end
  end

  describe "post_to_tracker/3" do
    test "posts each result as a card to an isolated tracker store" do
      store =
        start_supervised!(
          {SoundForge.Tracker.Store, name: :"tracker_#{System.unique_integer([:positive])}"}
        )

      assert {:ok, 2} = Reporter.post_to_tracker("run-1", results(), tracker: store)

      snapshot = SoundForge.Tracker.Store.snapshot(store)
      cards = Enum.map(snapshot.cards, & &1.card)
      assert Enum.all?(cards, &(&1.source == "live_harness"))
      assert Enum.sort(Enum.map(cards, & &1.step_id)) == ["s1", "s2"]
    end
  end

  describe "report/3" do
    @tag :tmp_dir
    test "combines summary write and tracker posting", %{tmp_dir: tmp} do
      store =
        start_supervised!(
          {SoundForge.Tracker.Store, name: :"tracker_#{System.unique_integer([:positive])}"}
        )

      assert {:ok, %{path: path, tracker_cards: 2}} =
               Reporter.report("run-2", results(), root: tmp, tracker: store)

      assert File.exists?(path)
    end
  end
end
