defmodule SoundForge.LLM.Adapters.LMStudio do
  @moduledoc "Adapter for LM Studio (OpenAI-compatible local server)."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Adapters.OpenAICompatible

  @default_url "http://localhost:1234"

  @impl true
  def chat(provider, messages, opts \\ []) do
    base = String.trim_trailing(provider.base_url || @default_url, "/")
    url = "#{base}/v1/chat/completions"
    model = Keyword.get(opts, :model) || provider.default_model || "default"

    OpenAICompatible.chat(
      url: url,
      headers: [],
      model: model,
      messages: messages,
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      temperature: Keyword.get(opts, :temperature, 0.7),
      system: Keyword.get(opts, :system)
    )
  end
end
