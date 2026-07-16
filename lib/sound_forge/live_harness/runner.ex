defmodule SoundForge.LiveHarness.Runner do
  @moduledoc """
  Executes the live-harness catalog against a running SFA server.

  Port of vyynl-sales-web's `run-live-catalog.mjs`: fetches each route/API
  step over HTTP (Req), follows redirects manually so the final path is
  known, verifies expected text, and classifies each step as
  `:pass | :warn | :fail | :blocked` with evidence.
  """

  alias SoundForge.LiveHarness.Catalog
  alias SoundForge.LiveHarness.Catalog.Step

  @default_base_url "http://localhost:4000"
  @max_redirects 5

  @type result :: %{
          id: String.t(),
          criterion: String.t(),
          title: String.t(),
          kind: Step.kind(),
          status: :pass | :warn | :fail | :blocked,
          message: String.t(),
          evidence: String.t(),
          url: String.t() | nil,
          final_path: String.t() | nil
        }

  @doc """
  Runs steps against `base_url`. Options:

    * `:base_url` — defaults to `#{@default_base_url}`
    * `:steps` — list of `Step` structs (defaults to the full catalog)
    * `:root` — filesystem root for artifact checks (defaults to cwd)
  """
  @spec run(keyword()) :: {:ok, [result()]}
  def run(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    steps = Keyword.get(opts, :steps, Catalog.steps())
    root = Keyword.get(opts, :root, File.cwd!())

    {:ok, Enum.map(steps, &run_step(&1, base_url, root))}
  end

  @doc "Runs a single step."
  @spec run_step(Step.t(), String.t(), String.t()) :: result()
  def run_step(%Step{kind: kind} = step, base_url, _root)
      when kind in [:route, :api, :preflight] do
    case fetch(step, base_url) do
      {:ok, response} ->
        step |> classify_route(response, base_url) |> to_result(step)

      {:error, reason} ->
        to_result(
          %{
            status: :blocked,
            message: "Request failed: #{inspect(reason)}",
            evidence: "unreachable",
            url: join_url(base_url, step.path),
            final_path: nil
          },
          step
        )
    end
  end

  def run_step(%Step{kind: :artifact} = step, _base_url, root) do
    step |> classify_artifact(root) |> to_result(step)
  end

  def run_step(%Step{kind: kind} = step, _base_url, _root) when kind in [:journey, :manual] do
    to_result(
      %{
        status: :blocked,
        message: "#{kind} steps require manual or scripted verification.",
        evidence: "manual",
        url: nil,
        final_path: nil
      },
      step
    )
  end

  @doc """
  Pure classifier for HTTP responses (port of `classifyAppendixARouteResult`).

  `response` is `%{status: integer, url: String.t(), body: String.t()}` where
  `url` is the final URL after redirects.
  """
  @spec classify_route(Step.t(), map(), String.t()) :: map()
  def classify_route(%Step{} = step, %{status: status, url: url, body: body}, base_url) do
    requested_path = step.path && path_of(step.path, base_url)
    final_path = path_of(url, base_url)
    redirected = requested_path != nil and strip_query(final_path) != strip_query(requested_path)
    text_found = has_expected_text?(body, step.expected_text)
    accepted_redirect = redirected and strip_query(final_path) in step.accepted_redirect_paths
    expected_status = status in step.expected_statuses

    cond do
      status >= 500 ->
        %{
          status: :fail,
          message: "HTTP #{status}; route crashed during smoke.",
          evidence: "crash"
        }

      status == 404 ->
        %{
          status: if(step.warning_only, do: :warn, else: :fail),
          message: "HTTP 404; check feature flags or route availability.",
          evidence: "not-found"
        }

      status in [401, 403] ->
        %{
          status: :pass,
          message: "HTTP #{status}; guarded route responded without crashing.",
          evidence: "expected-auth-guard"
        }

      accepted_redirect ->
        %{
          status: :pass,
          message: "Safe recovery redirect to #{final_path}.",
          evidence: "safe-recovery-redirect"
        }

      redirected ->
        %{
          status: :warn,
          message:
            "Redirected from #{requested_path} to #{final_path}; smoke evidence only, not acceptance proof.",
          evidence: "route-smoke"
        }

      not expected_status ->
        %{
          status: if(step.warning_only, do: :warn, else: :fail),
          message: "HTTP #{status}; expected one of #{inspect(step.expected_statuses)}.",
          evidence: "unexpected-status"
        }

      not text_found ->
        %{
          status: :warn,
          message: "HTTP #{status}; route loaded but expected acceptance copy was not found.",
          evidence: "missing-acceptance-copy"
        }

      true ->
        %{status: :pass, message: "HTTP #{status}; acceptance copy detected.", evidence: "live"}
    end
    |> Map.merge(%{url: url, final_path: final_path})
  end

  @doc """
  True when the body contains at least one expected phrase (case-insensitive).
  An empty expectation list always matches.
  """
  @spec has_expected_text?(String.t() | nil, [String.t()]) :: boolean()
  def has_expected_text?(_body, []), do: true

  def has_expected_text?(body, expected_text) do
    normalized = String.downcase(to_string(body || ""))
    Enum.any?(expected_text, &String.contains?(normalized, String.downcase(&1)))
  end

  @doc "Pure classifier for artifact steps."
  @spec classify_artifact(Step.t(), String.t()) :: map()
  def classify_artifact(%Step{} = step, root) do
    missing = Enum.reject(step.artifact_paths, &File.exists?(Path.join(root, &1)))

    cond do
      missing != [] ->
        %{
          status: :fail,
          message: "Missing artifacts: #{Enum.join(missing, ", ")}",
          evidence: "missing-artifact",
          url: nil,
          final_path: nil
        }

      step.expected_text != [] ->
        contents =
          step.artifact_paths
          |> Enum.map(&File.read!(Path.join(root, &1)))
          |> Enum.join("\n")

        if has_expected_text?(contents, step.expected_text) do
          %{
            status: :pass,
            message: "All artifacts present with expected content.",
            evidence: "artifact",
            url: nil,
            final_path: nil
          }
        else
          %{
            status: :warn,
            message: "Artifacts present but expected content not found.",
            evidence: "weak-artifact",
            url: nil,
            final_path: nil
          }
        end

      true ->
        %{
          status: :pass,
          message: "All artifacts present.",
          evidence: "artifact",
          url: nil,
          final_path: nil
        }
    end
  end

  # -- HTTP -----------------------------------------------------------------

  defp fetch(%Step{} = step, base_url) do
    do_fetch(step.method, join_url(base_url, step.path), step.request_body, @max_redirects)
  end

  defp do_fetch(_method, url, _body, 0), do: {:ok, %{status: 310, url: url, body: ""}}

  defp do_fetch(method, url, body, redirects_left) do
    req_opts = [
      method: method,
      url: url,
      redirect: false,
      retry: false,
      receive_timeout: 10_000
    ]

    req_opts = if body, do: Keyword.put(req_opts, :json, body), else: req_opts

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
        case Req.Response.get_header(resp, "location") do
          [location | _] ->
            next = URI.merge(url, location) |> URI.to_string()
            do_fetch(:get, next, nil, redirects_left - 1)

          [] ->
            {:ok, %{status: status, url: url, body: body_text(resp)}}
        end

      {:ok, %Req.Response{status: status} = resp} ->
        {:ok, %{status: status, url: url, body: body_text(resp)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp body_text(%Req.Response{body: body}) when is_binary(body), do: body
  defp body_text(%Req.Response{body: body}), do: inspect(body)

  defp join_url(base_url, path), do: String.trim_trailing(base_url, "/") <> to_string(path)

  defp path_of(value, base_url) do
    uri = URI.merge(base_url, to_string(value))
    if uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path || "/"
  end

  defp strip_query(nil), do: nil
  defp strip_query(path), do: path |> String.split("?") |> hd()

  defp to_result(classification, %Step{} = step) do
    Map.merge(classification, %{
      id: step.id,
      criterion: step.criterion,
      title: step.title,
      kind: step.kind
    })
  end
end
