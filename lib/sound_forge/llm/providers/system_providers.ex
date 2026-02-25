defmodule SoundForge.LLM.Providers.SystemProviders do
  @moduledoc """
  Reads LLM provider credentials from environment variables and returns
  virtual (non-persisted) `SoundForge.LLM.Provider` structs.

  These act as fallback providers when a user has not configured their own.
  The returned structs have `id: nil` and are never written to the database.

  ## Supported Environment Variables

  | Variable               | Provider Type     | Field     |
  |------------------------|-------------------|-----------|
  | `ANTHROPIC_API_KEY`    | `:anthropic`      | api_key   |
  | `OPENAI_API_KEY`       | `:openai`         | api_key   |
  | `OPENAI_BASE_URL`      | `:openai`         | base_url  |
  | `AZURE_OPENAI_API_KEY` | `:azure_openai`   | api_key   |
  | `AZURE_OPENAI_ENDPOINT`| `:azure_openai`   | base_url  |
  | `GOOGLE_AI_API_KEY`    | `:google_gemini`  | api_key   |
  | `OLLAMA_BASE_URL`      | `:ollama`         | base_url  |
  | `LITELLM_BASE_URL`     | `:litellm`        | base_url  |
  | `LITELLM_API_KEY`      | `:litellm`        | api_key   |
  """

  alias SoundForge.LLM.Provider

  @type provider_def :: {atom(), String.t(), [{:api_key, String.t()} | {:base_url, String.t()}]}

  # Each entry: {provider_type, display_name, env_var_mappings}
  # The order here determines the default priority.
  @provider_defs [
    {:anthropic, "Anthropic (System)",
     [api_key: "ANTHROPIC_API_KEY"]},
    {:openai, "OpenAI (System)",
     [api_key: "OPENAI_API_KEY", base_url: "OPENAI_BASE_URL"]},
    {:azure_openai, "Azure OpenAI (System)",
     [api_key: "AZURE_OPENAI_API_KEY", base_url: "AZURE_OPENAI_ENDPOINT"]},
    {:google_gemini, "Google AI (System)",
     [api_key: "GOOGLE_AI_API_KEY"]},
    {:ollama, "Ollama (System)",
     [base_url: {"OLLAMA_BASE_URL", "http://localhost:11434"}]},
    {:litellm, "LiteLLM (System)",
     [base_url: "LITELLM_BASE_URL", api_key: "LITELLM_API_KEY"]}
  ]

  @doc """
  Returns a list of virtual `Provider` structs built from environment variables.

  Only providers whose required credential is present are included. Cloud
  providers require an `api_key`; local/proxy providers require a `base_url`.

  The structs have `id: nil`, `enabled: true`, and sequential priorities
  starting at `1000` (so they sort after user-configured providers).
  """
  @spec list_system_providers() :: [Provider.t()]
  def list_system_providers do
    @provider_defs
    |> Enum.with_index()
    |> Enum.reduce([], fn {{provider_type, name, env_mappings}, index}, acc ->
      fields = resolve_env_fields(env_mappings)

      if provider_available?(provider_type, fields) do
        provider = build_provider(provider_type, name, fields, 1000 + index)
        [provider | acc]
      else
        acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Returns a single system provider by type, or `nil` if the required
  environment variable is not set.
  """
  @spec get_system_provider(atom()) :: Provider.t() | nil
  def get_system_provider(provider_type) do
    Enum.find(list_system_providers(), &(&1.provider_type == provider_type))
  end

  @doc """
  Returns `true` if at least one system provider has valid credentials.
  """
  @spec any_available?() :: boolean()
  def any_available? do
    list_system_providers() != []
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Resolves env var names to their runtime values.
  # Supports plain string env var names and `{env_var, default}` tuples.
  defp resolve_env_fields(env_mappings) do
    Enum.reduce(env_mappings, %{}, fn {field, env_spec}, acc ->
      value = resolve_env_value(env_spec)

      if value do
        Map.put(acc, field, value)
      else
        acc
      end
    end)
  end

  defp resolve_env_value({env_var, default}) when is_binary(env_var) do
    case System.get_env(env_var) do
      nil -> default
      "" -> default
      val -> val
    end
  end

  defp resolve_env_value(env_var) when is_binary(env_var) do
    case System.get_env(env_var) do
      nil -> nil
      "" -> nil
      val -> val
    end
  end

  # Cloud providers need an api_key; local/proxy providers need a base_url.
  defp provider_available?(provider_type, fields) do
    cond do
      provider_type in Provider.cloud_providers() ->
        Map.has_key?(fields, :api_key)

      provider_type in Provider.local_providers() ->
        Map.has_key?(fields, :base_url)

      true ->
        false
    end
  end

  defp build_provider(provider_type, name, fields, priority) do
    %Provider{
      id: nil,
      provider_type: provider_type,
      name: name,
      api_key: Map.get(fields, :api_key),
      base_url: Map.get(fields, :base_url),
      default_model: default_model_for(provider_type),
      enabled: true,
      priority: priority,
      health_status: :unknown,
      last_health_check_at: nil,
      config_json: %{"system" => true}
    }
  end

  defp default_model_for(:anthropic), do: "claude-sonnet-4-20250514"
  defp default_model_for(:openai), do: "gpt-4o"
  defp default_model_for(:azure_openai), do: "gpt-4o"
  defp default_model_for(:google_gemini), do: "gemini-2.0-flash"
  defp default_model_for(:ollama), do: "llama3.2"
  defp default_model_for(:litellm), do: nil
  defp default_model_for(_), do: nil
end
