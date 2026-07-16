defmodule SoundForge.LiveHarness.CatalogTest do
  use ExUnit.Case, async: true

  alias SoundForge.LiveHarness.Catalog
  alias SoundForge.LiveHarness.Catalog.Step

  describe "steps/0" do
    test "is non-empty and every step validates" do
      steps = Catalog.steps()
      refute Enum.empty?(steps)

      for step <- steps do
        assert {:ok, _} = Catalog.validate(step), "invalid step: #{step.id}"
      end
    end

    test "step ids are unique" do
      ids = Catalog.step_ids()
      assert ids == Enum.uniq(ids)
    end

    test "all kinds are valid" do
      kinds = Catalog.kinds()

      for step <- Catalog.steps() do
        assert step.kind in kinds
      end
    end

    test "route/api/preflight steps have paths" do
      for %Step{kind: kind} = step <- Catalog.steps(), kind in [:route, :api, :preflight] do
        assert is_binary(step.path) and String.starts_with?(step.path, "/")
      end
    end

    test "artifact steps have artifact_paths" do
      for %Step{kind: :artifact} = step <- Catalog.steps() do
        assert step.artifact_paths != []
      end
    end

    test "covers the core SFA routes" do
      paths = Catalog.steps() |> Enum.map(& &1.path)

      for path <- [
            "/",
            "/crate",
            "/daw",
            "/practice",
            "/samples",
            "/alchemy",
            "/admin",
            "/health"
          ] do
        assert path in paths, "missing catalog coverage for #{path}"
      end
    end
  end

  describe "get/1" do
    test "returns a step by id" do
      assert {:ok, %Step{id: "sfa-dashboard"}} = Catalog.get("sfa-dashboard")
    end

    test "returns :not_found for unknown ids" do
      assert {:error, :not_found} = Catalog.get("nope")
    end
  end

  describe "validate/1" do
    test "rejects a step with an invalid kind and missing target" do
      step = %Step{id: "x", criterion: "S9", title: "x", kind: :bogus}
      assert {:error, errors} = Catalog.validate(step)
      assert Enum.any?(errors, &(&1 =~ "invalid kind"))
    end

    test "rejects a route step without a path" do
      step = %Step{id: "x", criterion: "S9", title: "x", kind: :route}
      assert {:error, errors} = Catalog.validate(step)
      assert "route steps require a path" in errors
    end

    test "rejects an artifact step without artifact_paths" do
      step = %Step{id: "x", criterion: "S9", title: "x", kind: :artifact}
      assert {:error, errors} = Catalog.validate(step)
      assert "artifact steps require artifact_paths" in errors
    end
  end
end
