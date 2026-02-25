defmodule SoundForge.LLM.Adapters.Anthropic do
  @moduledoc "Adapter for the Anthropic Messages API."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Response
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  @impl true
  def chat(provider, messages, opts \\ []) do
    api_key = provider.api_key
    model = Keyword.get(opts, :model) || provider.default_model || "claude-sonnet-4-20250514"
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    temperature = Keyword.get(opts, :temperature, 0.7)
    system = Keyword.get(opts, :system)

    unless api_key do
      {:error, :missing_api_key}
    else
      body =
        %{
          "model" => model,
          "max_tokens" => max_tokens,
          "temperature" => temperature,
          "messages" => normalize_messages(messages)
        }
        |> maybe_add_system(system)

      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]

      url = (provider.base_url || @api_url) |> String.trim_trailing("/")
      url = if String.ends_with?(url, "/v1/messages"), do: url, else: url <> "/v1/messages"

      case Req.post(url, json: body, headers: headers, receive_timeout: 120_000) do
        {:ok, %{status: 200, body: resp_body}} ->
          parse_response(resp_body)

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:http_error, status, inspect(resp_body)}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp parse_response(%{"content" => content, "model" => model} = body) do
    text =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map_join("", & &1["text"])

    usage =
      case Map.get(body, "usage") do
        %{"input_tokens" => it, "output_tokens" => ot} ->
          %{input_tokens: it, output_tokens: ot, total_tokens: it + ot}

        _ ->
          %{}
      end

    {:ok,
     %Response{
       content: text,
       model: model,
       usage: usage,
       finish_reason: Map.get(body, "stop_reason"),
       raw_response: body
     }}
  end

  defp parse_response(body), do: {:error, {:unexpected_response, body}}

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} -> %{"role" => to_string(role), "content" => content}
      %{"role" => _, "content" => _} = m -> m
      other -> %{"role" => "user", "content" => to_string(other)}
    end)
  end

  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, ""), do: body
  defp maybe_add_system(body, system), do: Map.put(body, "system", system)
end
