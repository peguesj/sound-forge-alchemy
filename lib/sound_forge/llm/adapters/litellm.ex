defmodule SoundForge.LLM.Adapters.LiteLLM do
  @moduledoc """
  Adapter for LiteLLM proxy (OpenAI-compatible with multi-provider routing).

  LiteLLM is the recommended provider as it can proxy to many backends
  with a single integration. Model names can include provider prefixes
  like "anthropic/claude-sonnet-4-20250514" or "openai/gpt-4o".
  """
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Adapters.OpenAICompatible

  @impl true
  def chat(provider, messages, opts \\ []) do
    base = String.trim_trailing(provider.base_url || "http://localhost:4000", "/")
    url = "#{base}/chat/completions"
    model = Keyword.get(opts, :model) || provider.default_model

    unless model do
      {:error, :no_model_specified}
    else
      headers =
        if provider.api_key do
          [{"authorization", "Bearer #{provider.api_key}"}]
        else
          []
        end

      OpenAICompatible.chat(
        url: url,
        headers: headers,
        model: model,
        messages: messages,
        max_tokens: Keyword.get(opts, :max_tokens, 4096),
        temperature: Keyword.get(opts, :temperature, 0.7),
        system: Keyword.get(opts, :system)
      )
    end
  end
end
