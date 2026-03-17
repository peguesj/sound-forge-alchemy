defmodule SoundForge.BigLoopy.RecipeParser do
  @moduledoc """
  Uses the LLM router to interpret a natural language alchemy recipe into
  a structured loop configuration.

  Input: A recipe text string like "Give me 4 tight drum loops and 2 bass grooves,
         keep everything around 120 BPM".
  Output: {:ok, %{loops: [...], stems: [...], bpm_target: float}} or {:error, reason}
  """

  require Logger

  @system_prompt """
  You are an audio loop extraction assistant for Sound Forge Alchemy.

  The user will describe a recipe for extracting loops from audio stems.
  Parse their request and return a JSON object with exactly this structure:
  {
    "loops": [
      {"label": "string", "stem": "drums|bass|vocals|melody|other", "duration_beats": 4, "count": 1}
    ],
    "stems": ["drums", "bass", "vocals", "melody", "other"],
    "bpm_target": 120.0,
    "notes": "any extra instructions"
  }

  Rules:
  - Each loop entry specifies what kind of loop segment to extract
  - stems is the list of stem types to use
  - bpm_target is the desired tempo (default 120 if not specified)
  - duration_beats is how many beats long each loop should be (default 8)
  - count is how many of that loop type to extract (default 1)
  - Only return valid JSON, no markdown, no explanation
  """

  @doc """
  Parses a natural language recipe into a structured loop configuration.

  Returns `{:ok, %{loops: [...], stems: [...], bpm_target: float}}` or `{:error, reason}`.
  Falls back gracefully with `{:error, :llm_unavailable}` if no LLM is configured.
  """
  @spec parse(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def parse(user_id, recipe_text) when is_binary(recipe_text) do
    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: recipe_text}
    ]

    task_spec = %{
      task_type: :text_generation,
      prefer: :quality,
      max_tokens: 512,
      temperature: 0.2
    }

    Logger.debug("[RecipeParser] Parsing recipe for user #{user_id}: #{String.slice(recipe_text, 0, 80)}...")

    case SoundForge.LLM.Router.route(user_id, messages, task_spec) do
      {:ok, response} ->
        parse_llm_response(response)

      {:error, :no_providers_available} ->
        Logger.info("[RecipeParser] No LLM providers configured — using default recipe")
        {:error, :llm_unavailable}

      {:error, reason} ->
        Logger.warning("[RecipeParser] LLM routing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp parse_llm_response(response) do
    content = extract_content(response)

    case Jason.decode(content) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, normalize_recipe(parsed)}

      {:error, _} ->
        # Try to extract JSON from the response if it has surrounding text
        case extract_json_from_text(content) do
          {:ok, parsed} -> {:ok, normalize_recipe(parsed)}
          :error -> {:error, :invalid_llm_response}
        end
    end
  end

  defp extract_content(%{content: content}) when is_binary(content), do: String.trim(content)
  defp extract_content(%{"content" => content}) when is_binary(content), do: String.trim(content)
  defp extract_content(response), do: inspect(response)

  defp extract_json_from_text(text) do
    case Regex.run(~r/\{[\s\S]*\}/, text) do
      [json_str | _] ->
        case Jason.decode(json_str) do
          {:ok, parsed} -> {:ok, parsed}
          _ -> :error
        end

      nil ->
        :error
    end
  end

  defp normalize_recipe(parsed) do
    %{
      loops: Map.get(parsed, "loops", [default_loop()]),
      stems: Map.get(parsed, "stems", ["drums", "bass"]),
      bpm_target: Map.get(parsed, "bpm_target", 120.0) |> to_float(),
      notes: Map.get(parsed, "notes", "")
    }
  end

  defp default_loop do
    %{"label" => "Loop", "stem" => "other", "duration_beats" => 8, "count" => 1}
  end

  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val * 1.0
  defp to_float(_), do: 120.0
end
