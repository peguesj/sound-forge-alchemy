defmodule SoundForge.Agents.SonicAnalyst do
  @moduledoc """
  Sonic Analyst agent — BPM detection, key analysis, mood/energy profiling,
  and mix compatibility scoring between two tracks.

  ## Triggers
    - `track_uploaded`
    - `analysis_requested`
    - `set_generation_requested`

  ## Payload fields
    - `:user_id` — user making the request
    - `:track_ids` — list of 1–2 track UUIDs to analyse / compare
    - `:instruction` — optional override for LLM task description

  ## Output (in AgentRegistry and PubSub broadcast)
    `{:ok, %Result{}}` where `result.content` is a map with:
      - `"compatibility_score"` — float 0–1 (if two tracks supplied)
      - `"tempo_match"` — boolean
      - `"key_compatible"` — boolean (Camelot wheel)
      - `"energy_delta"` — float (energy difference)
      - `"mix_notes"` — string
      - `"tracks"` — list of per-track analysis summaries
  """

  use SoundForge.Agents.Agent

  import Ecto.Query, warn: false

  alias SoundForge.Music.{AnalysisResult, Track}
  alias SoundForge.Repo

  @impl true
  def name, do: "agent-sonic-analyst"

  @impl true
  def description,
    do: "Profiles audio features (BPM, key, energy) and scores mix compatibility between tracks."

  @impl true
  def capabilities,
    do: [:audio_analysis, :bpm_detection, :key_analysis, :energy_profiling, :mix_compatibility]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :fast]

  @impl true
  def system_prompt do
    """
    You are a professional DJ and audio analyst. Your job is to:
    1. Analyse the musical properties of tracks: BPM, key, energy, genre cues.
    2. Score the mix compatibility between two tracks on a 0–1 scale.
    3. Check Camelot wheel compatibility for harmonic mixing.
    4. Provide concrete mix notes: optimal transition point, pitch shift needed, energy management.

    Return structured JSON only. Do not add prose outside the JSON object.

    Schema:
    {
      "compatibility_score": <float 0-1>,
      "tempo_match": <bool>,
      "key_compatible": <bool>,
      "energy_delta": <float>,
      "mix_notes": <string>,
      "tracks": [{"title": string, "bpm": number, "key": string, "energy": number}]
    }
    """
  end

  @impl true
  def run(%SoundForge.Agents.Context{} = ctx, opts) do
    track_ids = ctx.track_ids || (ctx.track_id && [ctx.track_id]) || []
    user_id = ctx.user_id

    # Load tracks and their analysis data
    tracks_with_analysis =
      track_ids
      |> Enum.map(&load_track_with_analysis/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(tracks_with_analysis) do
      {:error, :no_tracks_found}
    else
      track_summary = format_track_summary(tracks_with_analysis)

      instruction =
        ctx.instruction ||
          if length(tracks_with_analysis) >= 2 do
            "Score the mix compatibility between these two tracks and provide mix notes."
          else
            "Analyse the audio properties of this track."
          end

      messages = format_messages(nil, [
        %{"role" => "user", "content" => "#{instruction}\n\n#{track_summary}"}
      ])

      case call_llm(user_id, messages, Keyword.merge([max_tokens: 512], opts)) do
        {:ok, %SoundForge.LLM.Response{} = response} ->
          parsed = parse_json_response(response.content)

          {:ok,
           SoundForge.Agents.Result.ok(__MODULE__, parsed,
             usage: response.usage,
             metadata: %{track_ids: track_ids}
           )}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -- Private helpers --

  defp load_track_with_analysis(track_id) do
    track = Repo.get(Track, track_id)
    analysis = track && Repo.one(from a in AnalysisResult, where: a.track_id == ^track_id, limit: 1)
    track && %{track: track, analysis: analysis}
  end

  defp format_track_summary(tracks_with_analysis) do
    tracks_with_analysis
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {%{track: track, analysis: analysis}, i} ->
      bpm = analysis && analysis.tempo && Float.round(analysis.tempo * 1.0, 1)
      key = analysis && analysis.key
      energy = analysis && analysis.energy

      "Track #{i}: \"#{track.title}\" by #{track.artist || "Unknown"}" <>
        (if bpm, do: " | BPM: #{bpm}", else: "") <>
        (if key, do: " | Key: #{key}", else: "") <>
        (if energy, do: " | Energy: #{Float.round(energy * 1.0, 2)}", else: "")
    end)
  end

  defp parse_json_response(content) when is_binary(content) do
    content
    |> String.trim()
    |> then(fn s ->
      # Strip markdown code fences if present
      Regex.replace(~r/^```json?\n?|```$/, s, "")
    end)
    |> Jason.decode()
    |> case do
      {:ok, map} -> map
      _ -> %{"raw_response" => content}
    end
  end

  defp parse_json_response(content), do: %{"raw_response" => inspect(content)}
end
