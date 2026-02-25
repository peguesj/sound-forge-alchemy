defmodule SoundForge.LLM.Client do
  @moduledoc """
  Unified LLM client that routes requests to the correct provider adapter.

  All adapters implement the same `chat/3` callback and normalize responses
  to `%SoundForge.LLM.Response{}`.
  """

  alias SoundForge.LLM.Response

  @callback chat(provider :: map(), messages :: list(), opts :: keyword()) ::
              {:ok, Response.t()} | {:error, term()}

  @doc """
  Sends a chat request to the appropriate adapter based on provider_type.

  ## Options
  - `:model` - Override the provider's default_model
  - `:max_tokens` - Maximum tokens in response (default: 4096)
  - `:temperature` - Sampling temperature (default: 0.7)
  - `:system` - System prompt string
  """
  @spec chat(map(), list(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def chat(%{provider_type: type} = provider, messages, opts \\ []) do
    adapter = adapter_for(type)
    adapter.chat(provider, messages, opts)
  rescue
    e -> {:error, {:adapter_error, Exception.message(e)}}
  end

  @doc "Returns the adapter module for a given provider type."
  @spec adapter_for(atom()) :: module()
  def adapter_for(:anthropic), do: SoundForge.LLM.Adapters.Anthropic
  def adapter_for(:openai), do: SoundForge.LLM.Adapters.OpenAI
  def adapter_for(:azure_openai), do: SoundForge.LLM.Adapters.AzureOpenAI
  def adapter_for(:google_gemini), do: SoundForge.LLM.Adapters.GoogleGemini
  def adapter_for(:ollama), do: SoundForge.LLM.Adapters.Ollama
  def adapter_for(:lm_studio), do: SoundForge.LLM.Adapters.LMStudio
  def adapter_for(:litellm), do: SoundForge.LLM.Adapters.LiteLLM
  def adapter_for(:custom_openai), do: SoundForge.LLM.Adapters.CustomOpenAI
  def adapter_for(type), do: raise("Unknown provider type: #{inspect(type)}")

  @doc "Tests connectivity to a provider. Returns :ok or {:error, reason}."
  @spec test_connection(map()) :: :ok | {:error, term()}
  def test_connection(provider) do
    case chat(provider, [%{role: "user", content: "Say OK"}], max_tokens: 8) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lightweight connectivity ping for a provider.

  Cloud providers (anthropic, openai, google_gemini, azure_openai) are checked
  with a cheap authenticated HTTP request.  Local providers (ollama, lm_studio,
  litellm, custom_openai) are probed via their health/model list endpoint.

  Returns `:ok`, `{:error, :timeout}`, or `{:error, reason}`.
  """
  @spec ping(map()) :: :ok | {:error, :timeout} | {:error, term()}
  def ping(%{provider_type: type} = provider) do
    url = ping_url(type, provider)
    headers = ping_headers(type, provider)

    case :httpc.request(:get, {String.to_charlist(url), headers}, [{:timeout, 8000}], []) do
      {:ok, {{_, status, _}, _, _}} when status in 200..499 ->
        :ok

      {:error, {:failed_connect, [{:to_address, _}, {:inet, _, :econnrefused}]}} ->
        {:error, :connection_refused}

      {:error, {:failed_connect, _}} ->
        {:error, :connection_refused}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :unknown}
    end
  rescue
    _ -> {:error, :unknown}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  @cloud_providers ~w(anthropic openai google_gemini azure_openai)a
  @local_providers ~w(ollama lm_studio litellm custom_openai)a

  defp ping_url(type, provider) when type in @cloud_providers do
    case type do
      :anthropic -> "https://api.anthropic.com/v1/models"
      :openai -> "https://api.openai.com/v1/models"
      :google_gemini -> "https://generativelanguage.googleapis.com/v1beta/models"
      :azure_openai ->
        base = Map.get(provider, :base_url, "")
        "#{base}/openai/deployments"
    end
  end

  defp ping_url(type, provider) when type in @local_providers do
    base = Map.get(provider, :base_url, "http://localhost:11434")

    case type do
      :ollama -> "#{base}/api/tags"
      _ -> "#{base}/v1/models"
    end
  end

  defp ping_url(_type, provider) do
    Map.get(provider, :base_url, "http://localhost:11434")
  end

  defp ping_headers(type, provider) when type in @cloud_providers do
    api_key = decrypt_api_key(provider)

    if api_key do
      auth_header =
        case type do
          :anthropic -> {~c"x-api-key", String.to_charlist(api_key)}
          _ -> {~c"authorization", String.to_charlist("Bearer #{api_key}")}
        end

      [auth_header]
    else
      []
    end
  end

  defp ping_headers(_type, _provider), do: []

  defp decrypt_api_key(%{api_key: nil}), do: nil
  defp decrypt_api_key(%{api_key: key}) when is_binary(key), do: key
  defp decrypt_api_key(_), do: nil
end
