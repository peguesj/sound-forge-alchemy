defmodule SoundForge.Agents.CrateAnalyst do
  @moduledoc """
  Crate Analyst agent — AI-powered "Crate DNA" analysis.

  Given a crate_id, loads the crate's track list and computed profile, then
  asks the LLM to generate:
    - Genre boundary tags
    - Era/decade range
    - Mood arc description
    - DNA summary (2–3 sentence natural language characterisation)
    - Suggested use cases (e.g. "peak-hour set opener", "warm-up room")

  ## Trigger

      SoundForge.Agents.trigger("agent-crate-analyst", %{
        crate_id: "uuid",
        user_id: 42
      })

  ## Output

      {:ok, %Result{content: %{
        "genre_tags" => ["deep house", "afro-tech"],
        "era_range" => "2018–2024",
        "mood_arc" => "Hypnotic and percussive, building toward euphoric release",
        "dna_summary" => "...",
        "suggested_use_cases" => ["peak-hour set", "after-hours room"]
      }}}
  """

  use SoundForge.Agents.Agent

  alias SoundForge.CrateDigger

  @impl true
  def name, do: "agent-crate-analyst"

  @impl true
  def description,
    do: "Analyses a crate's tracks to produce genre tags, era range, mood arc, and DNA summary."

  @impl true
  def capabilities, do: [:crate_analysis, :genre_detection, :mood_profiling]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :balanced]

  @impl true
  def system_prompt do
    """
    You are a music curator and analyst specialising in electronic and contemporary music.
    Given a list of tracks and optional audio feature statistics, produce a concise "crate DNA" card.

    Return ONLY valid JSON — no prose outside the JSON object.

    Schema:
    {
      "genre_tags": [<string>, ...],
      "era_range": "<string, e.g. '2018-2024'>",
      "mood_arc": "<one sentence describing the emotional/energy arc of the crate>",
      "dna_summary": "<2-3 sentence natural language characterisation>",
      "suggested_use_cases": [<string>, ...]
    }
    """
  end

  @impl true
  def run(%SoundForge.Agents.Context{} = ctx, opts) do
    crate_id = get_in(ctx.data, ["crate_id"]) || get_in(ctx.data, [:crate_id])
    user_id = ctx.user_id

    crate = crate_id && CrateDigger.get_crate(crate_id)

    if is_nil(crate) do
      {:error, :crate_not_found}
    else
      track_summary = format_track_list(crate)
      profile_summary = format_profile(crate.crate_profile)

      user_content =
        """
        Analyse this crate: "#{crate.name}" (#{length(crate.playlist_data)} tracks)

        #{profile_summary}

        Tracks:
        #{track_summary}
        """

      messages =
        format_messages(nil, [
          %{"role" => "user", "content" => user_content}
        ])

      case call_llm(user_id, messages, Keyword.merge([max_tokens: 600], opts)) do
        {:ok, %SoundForge.LLM.Response{} = response} ->
          parsed = parse_json_response(response.content)

          {:ok,
           SoundForge.Agents.Result.ok(__MODULE__, parsed,
             usage: response.usage,
             metadata: %{crate_id: crate_id, crate_name: crate.name}
           )}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_track_list(%{playlist_data: tracks}) do
    tracks
    |> Enum.take(40)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {t, i} ->
      "#{i}. \"#{t["title"] || "Unknown"}\" by #{t["artist"] || "Unknown"}" <>
        (if t["release_date"], do: " (#{String.slice(t["release_date"], 0, 4)})", else: "")
    end)
  end

  defp format_profile(nil), do: ""
  defp format_profile(profile) when map_size(profile) == 0, do: ""

  defp format_profile(profile) do
    parts =
      [
        profile["bpm_center"] && "BPM center: #{profile["bpm_center"]}",
        profile["top_keys"] && !Enum.empty?(profile["top_keys"]) &&
          "Top keys: #{Enum.join(profile["top_keys"], ", ")}",
        profile["energy_mean"] && "Energy mean: #{Float.round(profile["energy_mean"], 2)}"
      ]
      |> Enum.reject(&(!&1))

    if Enum.empty?(parts), do: "", else: "\nAudio profile: #{Enum.join(parts, " | ")}"
  end

  defp parse_json_response(content) when is_binary(content) do
    content
    |> String.trim()
    |> then(fn s -> Regex.replace(~r/^```json?\n?|```$/, s, "") end)
    |> Jason.decode()
    |> case do
      {:ok, map} -> map
      _ -> %{"raw_response" => content}
    end
  end

  defp parse_json_response(content), do: %{"raw_response" => inspect(content)}
end
