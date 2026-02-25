defmodule SoundForge.LLM.Adapters.Ollama do
  @moduledoc "Adapter for the Ollama local inference API."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Response

  @default_url "http://localhost:11434"

  @impl true
  def chat(provider, messages, opts \\ []) do
    base = String.trim_trailing(provider.base_url || @default_url, "/")
    url = "#{base}/api/chat"
    model = Keyword.get(opts, :model) || provider.default_model || "llama3.2"
    system = Keyword.get(opts, :system)

    msgs = normalize_messages(messages, system)

    body = %{"model" => model, "messages" => msgs, "stream" => false}

    case Req.post(url, json: body, receive_timeout: 300_000) do
      {:ok, %{status: 200, body: resp_body}} ->
        parse_response(resp_body)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, inspect(resp_body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_response(%{"message" => %{"content" => content}} = body) do
    model = Map.get(body, "model")

    usage =
      case Map.get(body, "eval_count") do
        nil -> %{}
        eval -> %{output_tokens: eval, input_tokens: Map.get(body, "prompt_eval_count", 0)}
      end

    {:ok, %Response{content: content, model: model, usage: usage, finish_reason: "stop", raw_response: body}}
  end

  defp parse_response(body), do: {:error, {:unexpected_response, body}}

  defp normalize_messages(messages, system) do
    sys = if system, do: [%{"role" => "system", "content" => system}], else: []

    msgs =
      Enum.map(messages, fn
        %{role: role, content: content} -> %{"role" => to_string(role), "content" => content}
        %{"role" => _, "content" => _} = m -> m
        other -> %{"role" => "user", "content" => to_string(other)}
      end)

    sys ++ msgs
  end
end
