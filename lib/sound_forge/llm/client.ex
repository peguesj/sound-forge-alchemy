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
end
