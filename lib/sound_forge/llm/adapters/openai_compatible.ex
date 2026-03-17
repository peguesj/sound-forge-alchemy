defmodule SoundForge.LLM.Adapters.OpenAICompatible do
  @moduledoc """
  Shared implementation for OpenAI-compatible APIs (OpenAI, Azure, LM Studio,
  LiteLLM, and custom endpoints). Individual adapters delegate to this module
  with provider-specific URL and header construction.
  """

  alias SoundForge.LLM.Response
  require Logger

  @doc """
  Sends a chat completion request to an OpenAI-compatible endpoint.

  ## Options
  - `:url` - Full URL for the chat completions endpoint
  - `:headers` - List of {key, value} header tuples
  - `:model` - Model name override
  - `:max_tokens` - Max response tokens (default 4096)
  - `:temperature` - Sampling temperature (default 0.7)
  - `:system` - System prompt (prepended as system message)
  """
  @spec chat(keyword()) :: {:ok, Response.t()} | {:error, term()}
  def chat(opts) do
    url = Keyword.fetch!(opts, :url)
    headers = Keyword.get(opts, :headers, [])
    model = Keyword.fetch!(opts, :model)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)
    messages = Keyword.fetch!(opts, :messages)
    system = Keyword.get(opts, :system)

    messages =
      if system do
        [%{"role" => "system", "content" => system} | normalize_messages(messages)]
      else
        normalize_messages(messages)
      end

    body =
      %{"model" => model, "messages" => messages}
      |> put_token_limit(model, max_tokens)
      |> maybe_put_temperature(model, temperature)

    case Req.post(url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        parse_openai_response(resp_body)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, inspect(resp_body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # o-series and GPT-5+ reasoning models use max_completion_tokens and don't support temperature
  @reasoning_model_pattern ~r/^(o1|o1-mini|o1-preview|o3|o3-mini|o4|o4-mini|gpt-5)/i

  defp reasoning_model?(model) when is_binary(model),
    do: Regex.match?(@reasoning_model_pattern, model)

  defp reasoning_model?(_), do: false

  defp put_token_limit(body, model, max_tokens) do
    key = if reasoning_model?(model), do: "max_completion_tokens", else: "max_tokens"
    Map.put(body, key, max_tokens)
  end

  defp maybe_put_temperature(body, model, temperature) do
    if reasoning_model?(model), do: body, else: Map.put(body, "temperature", temperature)
  end

  defp parse_openai_response(%{"choices" => [first | _]} = body) do
    content = get_in(first, ["message", "content"])
    finish_reason = Map.get(first, "finish_reason")
    model = Map.get(body, "model")

    usage =
      case Map.get(body, "usage") do
        %{"prompt_tokens" => pt, "completion_tokens" => ct, "total_tokens" => tt} ->
          %{input_tokens: pt, output_tokens: ct, total_tokens: tt}

        _ ->
          %{}
      end

    {:ok, %Response{content: content, model: model, usage: usage, finish_reason: finish_reason, raw_response: body}}
  end

  defp parse_openai_response(body) do
    {:error, {:unexpected_response, body}}
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{"role" => to_string(role), "content" => content}
      %{"role" => _, "content" => _} = m -> m
      other -> %{"role" => "user", "content" => to_string(other)}
    end)
  end
end
