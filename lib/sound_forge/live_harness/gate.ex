defmodule SoundForge.LiveHarness.Gate do
  @moduledoc """
  Environment gate for the live harness.

  The harness is enabled in `:dev` and `:test`, and in other lower
  environments only when `LIVE_HARNESS_ENABLED=true`. It is NEVER enabled
  in `:prod` regardless of environment variables (fail-closed, matching
  vyynl-sales-web's `environment-gate.ts` posture).
  """

  @doc """
  Whether the live harness may run. Accepts explicit inputs for testing:

    * `env` — the build environment atom (defaults to the current one)
    * `env_vars` — a map of environment variables
      (defaults to `System.get_env/0`)
  """
  @spec enabled?(atom(), %{optional(String.t()) => String.t()}) :: boolean()
  def enabled?(env \\ current_env(), env_vars \\ System.get_env())

  def enabled?(:prod, _env_vars), do: false
  def enabled?(env, _env_vars) when env in [:dev, :test], do: true

  def enabled?(_env, env_vars) do
    String.downcase(Map.get(env_vars, "LIVE_HARNESS_ENABLED", "")) == "true"
  end

  defp current_env do
    # Mix is unavailable in releases; fail closed to :prod there.
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      :prod
    end
  end
end
