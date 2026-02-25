defmodule SoundForge.LLM.Adapters.CustomOpenAI do
  @moduledoc "Adapter for any custom OpenAI-compatible API endpoint."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Adapters.OpenAICompatible

  @impl true
  def chat(provider, messages, opts \\ []) do
    base = String.trim_trailing(provider.base_url || "", "/")
    url = if String.ends_with?(base, "/chat/completions"), do: base, else: "#{base}/v1/chat/completions"
    model = Keyword.get(opts, :model) || provider.default_model || "default"

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
