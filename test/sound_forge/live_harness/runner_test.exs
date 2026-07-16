defmodule SoundForge.LiveHarness.RunnerTest do
  use ExUnit.Case, async: true

  alias SoundForge.LiveHarness.Catalog.Step
  alias SoundForge.LiveHarness.{Gate, Runner}

  @base_url "http://localhost:4000"

  defp step(attrs) do
    struct!(
      %Step{id: "t", criterion: "T1", title: "test step", kind: :route, path: "/x"},
      attrs
    )
  end

  defp response(attrs) do
    Map.merge(%{status: 200, url: @base_url <> "/x", body: ""}, attrs)
  end

  describe "has_expected_text?/2" do
    test "empty expectation always matches" do
      assert Runner.has_expected_text?("anything", [])
      assert Runner.has_expected_text?(nil, [])
    end

    test "matches any phrase, case-insensitively" do
      assert Runner.has_expected_text?("Welcome to SOUND Forge", ["sound forge"])
      assert Runner.has_expected_text?("abc", ["zzz", "AB"])
      refute Runner.has_expected_text?("abc", ["zzz"])
    end

    test "nil body never matches a non-empty expectation" do
      refute Runner.has_expected_text?(nil, ["x"])
    end
  end

  describe "classify_route/3" do
    test "5xx is a fail with crash evidence" do
      result = Runner.classify_route(step([]), response(%{status: 500}), @base_url)
      assert result.status == :fail
      assert result.evidence == "crash"
    end

    test "404 fails, or warns when warning_only" do
      assert Runner.classify_route(step([]), response(%{status: 404}), @base_url).status == :fail

      assert Runner.classify_route(step(warning_only: true), response(%{status: 404}), @base_url).status ==
               :warn
    end

    test "401/403 pass as expected auth guards" do
      for status <- [401, 403] do
        result = Runner.classify_route(step([]), response(%{status: status}), @base_url)
        assert result.status == :pass
        assert result.evidence == "expected-auth-guard"
      end
    end

    test "accepted redirect passes" do
      s = step(accepted_redirect_paths: ["/users/log-in"])
      resp = response(%{url: @base_url <> "/users/log-in"})
      result = Runner.classify_route(s, resp, @base_url)
      assert result.status == :pass
      assert result.evidence == "safe-recovery-redirect"
      assert result.final_path == "/users/log-in"
    end

    test "unexpected redirect warns" do
      resp = response(%{url: @base_url <> "/elsewhere"})
      result = Runner.classify_route(step([]), resp, @base_url)
      assert result.status == :warn
      assert result.evidence == "route-smoke"
    end

    test "expected status with matching text passes" do
      s = step(expected_text: ["hello"])
      result = Runner.classify_route(s, response(%{body: "<h1>Hello</h1>"}), @base_url)
      assert result.status == :pass
      assert result.evidence == "live"
    end

    test "expected status with missing text warns" do
      s = step(expected_text: ["hello"])
      result = Runner.classify_route(s, response(%{body: "nope"}), @base_url)
      assert result.status == :warn
      assert result.evidence == "missing-acceptance-copy"
    end

    test "unexpected non-error status fails" do
      s = step(expected_statuses: [200])
      result = Runner.classify_route(s, response(%{status: 302}), @base_url)
      assert result.status == :fail
      assert result.evidence == "unexpected-status"
    end

    test "query strings are ignored when comparing redirect paths" do
      s = step(path: "/x?foo=1")
      result = Runner.classify_route(s, response(%{url: @base_url <> "/x"}), @base_url)
      refute result.evidence == "route-smoke"
    end
  end

  describe "classify_artifact/2" do
    @tag :tmp_dir
    test "passes when artifacts exist with expected content", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "manifest.json"), ~s({"name": "SFA"}))
      s = step(kind: :artifact, artifact_paths: ["manifest.json"], expected_text: ["name"])
      assert Runner.classify_artifact(s, tmp).status == :pass
    end

    @tag :tmp_dir
    test "warns when content is missing expected text", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "sw.js"), "// empty")
      s = step(kind: :artifact, artifact_paths: ["sw.js"], expected_text: ["fetch"])
      result = Runner.classify_artifact(s, tmp)
      assert result.status == :warn
      assert result.evidence == "weak-artifact"
    end

    @tag :tmp_dir
    test "fails when an artifact is missing", %{tmp_dir: tmp} do
      s = step(kind: :artifact, artifact_paths: ["nope.json"])
      result = Runner.classify_artifact(s, tmp)
      assert result.status == :fail
      assert result.message =~ "nope.json"
    end
  end

  describe "run_step/3 for manual kinds" do
    test "journey and manual steps are blocked" do
      for kind <- [:journey, :manual] do
        result = Runner.run_step(step(kind: kind, path: nil), @base_url, ".")
        assert result.status == :blocked
        assert result.id == "t"
      end
    end
  end

  describe "Gate.enabled?/2" do
    test "never enabled in prod" do
      refute Gate.enabled?(:prod, %{"LIVE_HARNESS_ENABLED" => "true"})
    end

    test "enabled in dev and test" do
      assert Gate.enabled?(:dev, %{})
      assert Gate.enabled?(:test, %{})
    end

    test "other envs require the env var" do
      refute Gate.enabled?(:staging, %{})
      assert Gate.enabled?(:staging, %{"LIVE_HARNESS_ENABLED" => "true"})
      assert Gate.enabled?(:staging, %{"LIVE_HARNESS_ENABLED" => "TRUE"})
      refute Gate.enabled?(:staging, %{"LIVE_HARNESS_ENABLED" => "false"})
    end
  end
end
