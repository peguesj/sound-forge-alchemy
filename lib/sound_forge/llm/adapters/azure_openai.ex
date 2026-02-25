defmodule SoundForge.LLM.Adapters.AzureOpenAI do
  @moduledoc "Adapter for Azure OpenAI Service."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Adapters.OpenAICompatible

  @api_version "2024-02-01"

  @impl true
  def chat(provider, messages, opts \\ []) do
    model = Keyword.get(opts, :model) || provider.default_model || "gpt-4o"
    deployment = get_in(provider.config_json || %{}, ["deployment"]) || model

    base = String.trim_trailing(provider.base_url || "", "/")
    url = "#{base}/openai/deployments/#{deployment}/chat/completions?api-version=#{@api_version}"

    headers = [{"api-key", provider.api_key}]

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
