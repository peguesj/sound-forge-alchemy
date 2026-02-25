defmodule SoundForge.LLM.Adapters.OpenAI do
  @moduledoc "Adapter for the OpenAI Chat Completions API."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Adapters.OpenAICompatible

  @default_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def chat(provider, messages, opts \\ []) do
    url = (provider.base_url || @default_url) |> String.trim_trailing("/")
    url = if String.ends_with?(url, "/chat/completions"), do: url, else: url <> "/v1/chat/completions"
    model = Keyword.get(opts, :model) || provider.default_model || "gpt-4o"

    headers = [{"authorization", "Bearer #{provider.api_key}"}]

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
