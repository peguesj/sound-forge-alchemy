defmodule SoundForge.LiveHarness.Catalog do
  @moduledoc """
  Declarative step catalog for the SFA live integration harness.

  Ported from the vyynl-sales-web Appendix-A `live-harness-catalog.ts`.
  Each step declares what evidence proves a criterion is live, and the
  runner executes them against a running server.
  """

  alias SoundForge.LiveHarness.Catalog.Step

  @kinds [:route, :api, :journey, :preflight, :artifact, :manual]

  @steps [
    %Step{
      id: "sfa-preflight-server",
      criterion: "S0",
      title: "Phoenix server responds on the base URL",
      kind: :preflight,
      path: "/health",
      expected_statuses: [200],
      acceptance: "The harness only produces evidence against a live server."
    },
    %Step{
      id: "sfa-health-api",
      criterion: "S0",
      title: "Health endpoint reports system status",
      kind: :api,
      method: :get,
      path: "/health",
      expected_statuses: [200],
      expected_text: ["ok", "status"],
      acceptance: "Health check is queryable by deploy probes and the harness."
    },
    %Step{
      id: "sfa-tracker-health-api",
      criterion: "S0",
      title: "Tracker health endpoint is reachable",
      kind: :api,
      method: :get,
      path: "/api/tracker/health",
      expected_statuses: [200],
      expected_text: ["ok", "tracker"],
      warning_only: true,
      acceptance: "Tracker subsystem accepts live cards from the harness."
    },
    %Step{
      id: "sfa-tracker-state-api",
      criterion: "S0",
      title: "Tracker state endpoint returns run state",
      kind: :api,
      method: :get,
      path: "/api/tracker/state",
      expected_statuses: [200],
      expected_text: ["cards", "run", "state"],
      warning_only: true,
      acceptance: "Harness state can be queried by watchers and evidence boards."
    },
    %Step{
      id: "sfa-dashboard",
      criterion: "S1",
      title: "Dashboard root renders",
      kind: :route,
      path: "/",
      expected_statuses: [200],
      expected_text: ["sound forge", "track", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in"],
      acceptance: "Main dashboard (or its auth guard) renders without a crash."
    },
    %Step{
      id: "sfa-crate-digger",
      criterion: "S1",
      title: "CrateDigger route renders",
      kind: :route,
      path: "/crate",
      expected_statuses: [200],
      expected_text: ["crate", "playlist", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in", "/"],
      acceptance: "CrateDigger playlist player is reachable or safely guarded."
    },
    %Step{
      id: "sfa-daw",
      criterion: "S1",
      title: "DAW project route renders",
      kind: :route,
      path: "/daw",
      expected_statuses: [200],
      expected_text: ["daw", "project", "track", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in", "/"],
      acceptance: "Standalone DAW surface is reachable or safely guarded."
    },
    %Step{
      id: "sfa-practice",
      criterion: "S1",
      title: "Practice route renders",
      kind: :route,
      path: "/practice",
      expected_statuses: [200],
      expected_text: ["practice", "session", "melodics", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in", "/"],
      acceptance: "Melodics practice dashboard is reachable or safely guarded."
    },
    %Step{
      id: "sfa-samples",
      criterion: "S1",
      title: "Sample library route renders",
      kind: :route,
      path: "/samples",
      expected_statuses: [200],
      expected_text: ["sample", "library", "pack", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in", "/library", "/"],
      acceptance: "Sample library browser is reachable or safely guarded."
    },
    %Step{
      id: "sfa-alchemy",
      criterion: "S1",
      title: "BigLoopy alchemy route renders",
      kind: :route,
      path: "/alchemy",
      expected_statuses: [200],
      expected_text: ["bigloopy", "alchemy", "loop", "log in"],
      accepted_redirect_paths: ["/users/log-in", "/users/log_in", "/"],
      acceptance: "BigLoopy loop alchemy surface is reachable or safely guarded."
    },
    %Step{
      id: "sfa-admin-guard",
      criterion: "S2",
      title: "Admin dashboard is guarded for non-admins",
      kind: :route,
      path: "/admin",
      expected_statuses: [200, 302, 401, 403],
      expected_text: ["log in", "unauthorized", "admin"],
      accepted_redirect_paths: ["/", "/users/log-in", "/users/log_in"],
      acceptance: "Unauthenticated/non-admin requests are redirected or rejected, never a 5xx."
    },
    %Step{
      id: "sfa-pwa-manifest",
      criterion: "S3",
      title: "PWA manifest artifact exists",
      kind: :artifact,
      artifact_paths: ["priv/static/manifest.json"],
      expected_text: ["name", "display", "icons"],
      acceptance: "PWA manifest ships with the release so mobile install works."
    },
    %Step{
      id: "sfa-service-worker",
      criterion: "S3",
      title: "Service worker artifact exists",
      kind: :artifact,
      artifact_paths: ["priv/static/sw.js"],
      expected_text: ["fetch", "cache"],
      acceptance: "Service worker ships with the release for offline caching."
    }
  ]

  @doc "All catalog steps in execution order."
  @spec steps() :: [Step.t()]
  def steps, do: @steps

  @doc "All step ids."
  @spec step_ids() :: [String.t()]
  def step_ids, do: Enum.map(@steps, & &1.id)

  @doc "Valid step kinds."
  @spec kinds() :: [Step.kind()]
  def kinds, do: @kinds

  @doc "Fetch a step by id."
  @spec get(String.t()) :: {:ok, Step.t()} | {:error, :not_found}
  def get(id) do
    case Enum.find(@steps, &(&1.id == id)) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  @doc """
  Validates a step struct. Returns `{:ok, step}` or `{:error, reasons}`.
  """
  @spec validate(Step.t()) :: {:ok, Step.t()} | {:error, [String.t()]}
  def validate(%Step{} = step) do
    errors =
      []
      |> validate_present(step.id, "id is required")
      |> validate_present(step.criterion, "criterion is required")
      |> validate_present(step.title, "title is required")
      |> validate_kind(step)
      |> validate_target(step)

    case errors do
      [] -> {:ok, step}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_present(errors, value, message) do
    if value in [nil, ""], do: [message | errors], else: errors
  end

  defp validate_kind(errors, %Step{kind: kind}) when kind in @kinds, do: errors
  defp validate_kind(errors, %Step{kind: kind}), do: ["invalid kind: #{inspect(kind)}" | errors]

  defp validate_target(errors, %Step{kind: kind, path: path})
       when kind in [:route, :api, :preflight] and (is_nil(path) or path == ""),
       do: ["#{kind} steps require a path" | errors]

  defp validate_target(errors, %Step{kind: :artifact, artifact_paths: []}),
    do: ["artifact steps require artifact_paths" | errors]

  defp validate_target(errors, _step), do: errors
end
