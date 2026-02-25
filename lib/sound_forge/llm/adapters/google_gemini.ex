defmodule SoundForge.LLM.Adapters.GoogleGemini do
  @moduledoc "Adapter for the Google Gemini (Generative Language) API."
  @behaviour SoundForge.LLM.Client

  alias SoundForge.LLM.Response

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def chat(provider, messages, opts \\ []) do
    api_key = provider.api_key
    model = Keyword.get(opts, :model) || provider.default_model || "gemini-2.0-flash"
    max_tokens = Keyword.get(opts, :max_tokens, 4096)
    system = Keyword.get(opts, :system)

    unless api_key do
      {:error, :missing_api_key}
    else
      url = "#{@base_url}/models/#{model}:generateContent?key=#{api_key}"

      contents = normalize_messages(messages)

      body =
        %{"contents" => contents, "generationConfig" => %{"maxOutputTokens" => max_tokens}}
        |> maybe_add_system(system)

      case Req.post(url, json: body, receive_timeout: 120_000) do
        {:ok, %{status: 200, body: resp_body}} ->
          parse_response(resp_body, model)

        {:ok, %{status: status, body: resp_body}} ->
          {:error, {:http_error, status, inspect(resp_body)}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp parse_response(%{"candidates" => [first | _]} = body, model) do
    text = get_in(first, ["content", "parts", Access.at(0), "text"]) || ""
    finish_reason = Map.get(first, "finishReason")

    usage =
      case Map.get(body, "usageMetadata") do
        %{"promptTokenCount" => pt, "candidatesTokenCount" => ct, "totalTokenCount" => tt} ->
          %{input_tokens: pt, output_tokens: ct, total_tokens: tt}

        _ ->
          %{}
      end

    {:ok, %Response{content: text, model: model, usage: usage, finish_reason: finish_reason, raw_response: body}}
  end

  defp parse_response(body, _model), do: {:error, {:unexpected_response, body}}

  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: "system", content: _} -> nil
      %{"role" => "system", "content" => _} -> nil
      %{role: role, content: content} ->
        %{"role" => gemini_role(to_string(role)), "parts" => [%{"text" => content}]}
      %{"role" => role, "content" => content} ->
        %{"role" => gemini_role(role), "parts" => [%{"text" => content}]}
      other ->
        %{"role" => "user", "parts" => [%{"text" => to_string(other)}]}
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp gemini_role("assistant"), do: "model"
  defp gemini_role(role), do: role

  defp maybe_add_system(body, nil), do: body
  defp maybe_add_system(body, ""), do: body

  defp maybe_add_system(body, system) do
    Map.put(body, "systemInstruction", %{"parts" => [%{"text" => system}]})
  end
end
