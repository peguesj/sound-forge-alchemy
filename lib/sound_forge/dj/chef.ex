defmodule SoundForge.DJ.Chef do
  @moduledoc """
  AI-powered DJ track selection engine.

  Accepts a natural language prompt (e.g. "build me a deep house set that starts
  chill and builds energy") and a user ID, then:

  1. Calls the Anthropic API (Claude) to parse the prompt into a structured query
     with target genres, moods, tempo range, energy curve, and stem preferences.
  2. Queries the user's track library joined with analysis results.
  3. Ranks tracks by compatibility: tempo proximity, Camelot key compatibility,
     and energy curve fit.
  4. Returns a `%Chef.Recipe{}` with track recommendations, deck assignments,
     cue plans, stem loading instructions, and mixing notes.
  """

  import Ecto.Query, warn: false

  alias SoundForge.DJ.Chef.Recipe
  alias SoundForge.Music.AnalysisResult
  alias SoundForge.Music.Track
  alias SoundForge.Repo

  require Logger

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @model "claude-sonnet-4-20250514"
  @max_tokens 1024
  @default_bpm_tolerance 5.0
  @max_tracks 10

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Generates a DJ recipe from a natural language prompt.

  Parses the prompt via the Anthropic API into a structured intent, queries the
  user's analysed track library, ranks by musical compatibility, and assembles
  a `%Recipe{}` struct.

  ## Parameters

    * `prompt` -- natural language description of the desired set / mix
    * `user_id` -- integer ID of the user whose library to search

  ## Returns

    * `{:ok, %Recipe{}}` on success
    * `{:error, :missing_api_key}` if `ANTHROPIC_API_KEY` is not set
    * `{:error, :no_analysed_tracks}` if the user has no tracks with analysis data
    * `{:error, reason}` for API or parsing failures

  ## Examples

      iex> Chef.cook("deep house set, 120-125 BPM, build energy", 42)
      {:ok, %Recipe{tracks: [...]}}

  """
  @spec cook(String.t(), integer()) :: {:ok, Recipe.t()} | {:error, atom() | String.t()}
  def cook(prompt, user_id) when is_binary(prompt) and is_integer(user_id) do
    with {:ok, api_key} <- fetch_api_key(),
         {:ok, parsed_intent} <- parse_intent(prompt, api_key),
         {:ok, analysed_tracks} <- fetch_analysed_tracks(user_id),
         ranked <- rank_tracks(analysed_tracks, parsed_intent),
         selected <- Enum.take(ranked, @max_tracks) do
      recipe = build_recipe(prompt, parsed_intent, selected)
      {:ok, recipe}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 1 -- Fetch API key
  # ---------------------------------------------------------------------------

  @spec fetch_api_key() :: {:ok, String.t()} | {:error, :missing_api_key}
  defp fetch_api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil -> {:error, :missing_api_key}
      "" -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 2 -- Parse natural language intent via Anthropic API
  # ---------------------------------------------------------------------------

  @spec parse_intent(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp parse_intent(prompt, api_key) do
    system_prompt = """
    You are a DJ set planner AI. Given a natural language request, extract a \
    structured JSON object with the following fields:

    {
      "genres": ["genre1", "genre2"],
      "moods": ["mood1", "mood2"],
      "target_tempo_min": <number or null>,
      "target_tempo_max": <number or null>,
      "energy_curve": "ascending" | "descending" | "peak" | "steady" | "wave",
      "target_energy_min": <0.0-1.0 or null>,
      "target_energy_max": <0.0-1.0 or null>,
      "preferred_keys": ["key1", "key2"] or [],
      "stem_preferences": ["vocals", "drums", "bass", "other"] or [],
      "track_count": <integer, default 8>,
      "notes": "<any extra context>"
    }

    Rules:
    - Tempo values are BPM (beats per minute). Common ranges: house 118-130, \
    techno 125-145, hip-hop 80-100, drum-and-bass 160-180.
    - Energy is 0.0 (very chill) to 1.0 (peak energy).
    - If the user doesn't specify a field, use null or empty array.
    - Respond with ONLY the JSON object, no markdown fences, no explanation.
    """

    body = %{
      model: @model,
      max_tokens: @max_tokens,
      system: system_prompt,
      messages: [%{role: "user", content: prompt}]
    }

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @anthropic_version},
      {"content-type", "application/json"}
    ]

    case Req.post(@anthropic_url, headers: headers, json: body) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        extract_parsed_intent(resp_body)

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.error("Anthropic API returned #{status}: #{inspect(resp_body)}")
        {:error, "anthropic_api_error_#{status}"}

      {:error, reason} ->
        Logger.error("Anthropic API request failed: #{inspect(reason)}")
        {:error, "anthropic_api_request_failed"}
    end
  end

  @spec extract_parsed_intent(map()) :: {:ok, map()} | {:error, String.t()}
  defp extract_parsed_intent(%{"content" => [%{"text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, parsed} ->
        {:ok, normalize_intent(parsed)}

      {:error, _} ->
        Logger.warning("Failed to parse Anthropic response as JSON: #{text}")
        {:error, "invalid_llm_response"}
    end
  end

  defp extract_parsed_intent(body) do
    Logger.warning("Unexpected Anthropic response structure: #{inspect(body)}")
    {:error, "unexpected_llm_response"}
  end

  @spec normalize_intent(map()) :: map()
  defp normalize_intent(raw) do
    %{
      genres: Map.get(raw, "genres") || [],
      moods: Map.get(raw, "moods") || [],
      target_tempo_min: Map.get(raw, "target_tempo_min"),
      target_tempo_max: Map.get(raw, "target_tempo_max"),
      energy_curve: Map.get(raw, "energy_curve", "steady"),
      target_energy_min: Map.get(raw, "target_energy_min"),
      target_energy_max: Map.get(raw, "target_energy_max"),
      preferred_keys: Map.get(raw, "preferred_keys") || [],
      stem_preferences: Map.get(raw, "stem_preferences") || [],
      track_count: Map.get(raw, "track_count", 8),
      notes: Map.get(raw, "notes")
    }
  end

  # ---------------------------------------------------------------------------
  # Step 3 -- Fetch user's tracks with analysis data
  # ---------------------------------------------------------------------------

  @spec fetch_analysed_tracks(integer()) ::
          {:ok, [%{track: Track.t(), analysis: AnalysisResult.t()}]}
          | {:error, :no_analysed_tracks}
  defp fetch_analysed_tracks(user_id) do
    results =
      from(t in Track,
        join: ar in AnalysisResult,
        on: ar.track_id == t.id,
        where: t.user_id == ^user_id,
        select: {t, ar}
      )
      |> Repo.all()
      |> Enum.map(fn {track, analysis} -> %{track: track, analysis: analysis} end)

    case results do
      [] -> {:error, :no_analysed_tracks}
      tracks -> {:ok, tracks}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 4 -- Rank tracks by compatibility
  # ---------------------------------------------------------------------------

  @spec rank_tracks(
          [%{track: Track.t(), analysis: AnalysisResult.t()}],
          map()
        ) :: [%{track: Track.t(), analysis: AnalysisResult.t(), score: float()}]
  defp rank_tracks(tracks, intent) do
    tracks
    |> Enum.map(fn entry ->
      score = compute_compatibility_score(entry.analysis, intent)
      Map.put(entry, :score, score)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @spec compute_compatibility_score(AnalysisResult.t(), map()) :: float()
  defp compute_compatibility_score(analysis, intent) do
    tempo_score = tempo_compatibility(analysis.tempo, intent)
    key_score = key_compatibility(analysis.key, intent)
    energy_score = energy_compatibility(analysis.energy, intent)

    # Weighted average: tempo 40%, key 35%, energy 25%
    tempo_score * 0.40 + key_score * 0.35 + energy_score * 0.25
  end

  # -- Tempo scoring ----------------------------------------------------------

  @spec tempo_compatibility(float() | nil, map()) :: float()
  defp tempo_compatibility(nil, _intent), do: 0.0

  defp tempo_compatibility(tempo, intent) do
    min_bpm = intent[:target_tempo_min]
    max_bpm = intent[:target_tempo_max]

    cond do
      is_nil(min_bpm) and is_nil(max_bpm) ->
        # No tempo preference -- all tracks score equally
        1.0

      is_nil(min_bpm) ->
        distance = abs(tempo - max_bpm)
        score_from_distance(distance, @default_bpm_tolerance)

      is_nil(max_bpm) ->
        distance = abs(tempo - min_bpm)
        score_from_distance(distance, @default_bpm_tolerance)

      true ->
        mid = (min_bpm + max_bpm) / 2
        half_range = (max_bpm - min_bpm) / 2 + @default_bpm_tolerance

        distance = abs(tempo - mid)
        score_from_distance(distance, half_range)
    end
  end

  @spec score_from_distance(float(), float()) :: float()
  defp score_from_distance(distance, tolerance) do
    if distance <= tolerance do
      1.0
    else
      overshoot = distance - tolerance
      max(0.0, 1.0 - overshoot / tolerance)
    end
  end

  # -- Camelot key compatibility ----------------------------------------------

  @camelot_wheel %{
    # Minor keys (A column)
    "Ab minor" => "1A",
    "G# minor" => "1A",
    "Eb minor" => "2A",
    "D# minor" => "2A",
    "Bb minor" => "3A",
    "A# minor" => "3A",
    "F minor" => "4A",
    "C minor" => "5A",
    "G minor" => "6A",
    "D minor" => "7A",
    "A minor" => "8A",
    "E minor" => "9A",
    "B minor" => "10A",
    "F# minor" => "11A",
    "Gb minor" => "11A",
    "Db minor" => "12A",
    "C# minor" => "12A",
    # Major keys (B column)
    "B major" => "1B",
    "Cb major" => "1B",
    "F# major" => "2B",
    "Gb major" => "2B",
    "Db major" => "3B",
    "C# major" => "3B",
    "Ab major" => "4B",
    "G# major" => "4B",
    "Eb major" => "5B",
    "D# major" => "5B",
    "Bb major" => "6B",
    "A# major" => "6B",
    "F major" => "7B",
    "C major" => "8B",
    "G major" => "9B",
    "D major" => "10B",
    "A major" => "11B",
    "E major" => "12B"
  }

  @spec to_camelot(String.t() | nil) :: String.t() | nil
  defp to_camelot(nil), do: nil

  defp to_camelot(key) when is_binary(key) do
    # Try direct lookup first
    case Map.get(@camelot_wheel, key) do
      nil ->
        # Try normalising: "Cm" -> "C minor", "C" -> "C major"
        normalised = normalise_key_string(key)
        Map.get(@camelot_wheel, normalised)

      camelot ->
        camelot
    end
  end

  @spec normalise_key_string(String.t()) :: String.t()
  defp normalise_key_string(key) do
    trimmed = String.trim(key)

    cond do
      # Already in "X major"/"X minor" form
      String.contains?(trimmed, "major") or String.contains?(trimmed, "minor") ->
        trimmed

      # "Cm", "C#m", "Dbm" -> minor
      String.ends_with?(trimmed, "m") ->
        root = String.slice(trimmed, 0..(String.length(trimmed) - 2))
        "#{root} minor"

      # "CM", "C#M" -> major (less common notation)
      String.ends_with?(trimmed, "M") ->
        root = String.slice(trimmed, 0..(String.length(trimmed) - 2))
        "#{root} major"

      # Bare note name -> assume major
      true ->
        "#{trimmed} major"
    end
  end

  @doc """
  Determines whether two Camelot codes are compatible.

  Compatible means: same code, +/-1 on the number (wrapping 12<->1),
  or switching between A and B of the same number.
  """
  @spec camelot_compatible?(String.t(), String.t()) :: boolean()
  def camelot_compatible?(code_a, code_b) when is_binary(code_a) and is_binary(code_b) do
    case {parse_camelot(code_a), parse_camelot(code_b)} do
      {{num_a, col_a}, {num_b, col_b}} ->
        cond do
          # Same code
          num_a == num_b and col_a == col_b -> true
          # Same number, different column (A<->B switch)
          num_a == num_b -> true
          # Adjacent numbers, same column
          col_a == col_b and adjacent_camelot?(num_a, num_b) -> true
          true -> false
        end

      _ ->
        false
    end
  end

  def camelot_compatible?(_, _), do: false

  @spec parse_camelot(String.t()) :: {integer(), String.t()} | nil
  defp parse_camelot(code) do
    case Regex.run(~r/^(\d{1,2})([AB])$/, code) do
      [_, num_str, col] ->
        {String.to_integer(num_str), col}

      _ ->
        nil
    end
  end

  @spec adjacent_camelot?(integer(), integer()) :: boolean()
  defp adjacent_camelot?(a, b) do
    diff = abs(a - b)
    diff == 1 or diff == 11
  end

  @spec key_compatibility(String.t() | nil, map()) :: float()
  defp key_compatibility(nil, _intent), do: 0.0

  defp key_compatibility(key, intent) do
    preferred = intent[:preferred_keys] || []
    track_camelot = to_camelot(key)

    cond do
      # No key preference -- all keys score equally
      preferred == [] and is_nil(track_camelot) ->
        0.5

      preferred == [] ->
        # No preference but track has a key -- slight bonus for having data
        0.8

      is_nil(track_camelot) ->
        # Preference exists but track has no parseable key
        0.0

      true ->
        preferred_camelots =
          preferred
          |> Enum.map(&to_camelot/1)
          |> Enum.reject(&is_nil/1)

        if Enum.empty?(preferred_camelots) do
          0.8
        else
          if Enum.any?(preferred_camelots, &camelot_compatible?(track_camelot, &1)) do
            1.0
          else
            0.2
          end
        end
    end
  end

  # -- Energy scoring ---------------------------------------------------------

  @spec energy_compatibility(float() | nil, map()) :: float()
  defp energy_compatibility(nil, _intent), do: 0.0

  defp energy_compatibility(energy, intent) do
    min_e = intent[:target_energy_min]
    max_e = intent[:target_energy_max]

    cond do
      is_nil(min_e) and is_nil(max_e) ->
        # No energy preference
        1.0

      is_nil(min_e) ->
        if energy <= max_e, do: 1.0, else: max(0.0, 1.0 - (energy - max_e) * 2)

      is_nil(max_e) ->
        if energy >= min_e, do: 1.0, else: max(0.0, 1.0 - (min_e - energy) * 2)

      true ->
        if energy >= min_e and energy <= max_e do
          1.0
        else
          dist =
            if energy < min_e,
              do: min_e - energy,
              else: energy - max_e

          max(0.0, 1.0 - dist * 2)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Step 5 -- Build the Recipe struct
  # ---------------------------------------------------------------------------

  @spec build_recipe(
          String.t(),
          map(),
          [%{track: Track.t(), analysis: AnalysisResult.t(), score: float()}]
        ) :: Recipe.t()
  defp build_recipe(prompt, parsed_intent, selected_tracks) do
    tracks =
      Enum.map(selected_tracks, fn %{track: t, analysis: ar, score: score} ->
        %{
          track_id: t.id,
          title: t.title,
          artist: t.artist,
          tempo: ar.tempo,
          key: ar.key,
          energy: ar.energy,
          compatibility_score: Float.round(score, 3)
        }
      end)

    deck_assignments = assign_decks(tracks)
    cue_plan = build_cue_plan(selected_tracks)
    stems_to_load = build_stem_instructions(selected_tracks, parsed_intent)
    mixing_notes = generate_mixing_notes(tracks, parsed_intent)

    %Recipe{
      prompt: prompt,
      parsed_intent: parsed_intent,
      tracks: tracks,
      deck_assignments: deck_assignments,
      cue_plan: cue_plan,
      stems_to_load: stems_to_load,
      mixing_notes: mixing_notes,
      generated_at: DateTime.utc_now()
    }
  end

  # Alternate tracks between deck 1 and deck 2 for crossfade workflow
  @spec assign_decks([map()]) :: [Recipe.deck_assignment()]
  defp assign_decks(tracks) do
    tracks
    |> Enum.with_index()
    |> Enum.map(fn {track, idx} ->
      %{
        deck: if(rem(idx, 2) == 0, do: 1, else: 2),
        track_id: track.track_id,
        order: idx
      }
    end)
  end

  # Generate suggested cue points: a "mix in" cue at the start and a "drop"
  # cue at roughly the 25% mark (where intros typically end).
  @spec build_cue_plan([%{track: Track.t(), analysis: AnalysisResult.t(), score: float()}]) ::
          [Recipe.cue_plan_entry()]
  defp build_cue_plan(selected_tracks) do
    Enum.flat_map(selected_tracks, fn %{track: t} ->
      duration_ms = t.duration || 180_000

      [
        %{
          track_id: t.id,
          cue_type: :hot,
          position_ms: 0,
          label: "Mix In"
        },
        %{
          track_id: t.id,
          cue_type: :hot,
          position_ms: div(duration_ms, 4),
          label: "Drop"
        }
      ]
    end)
  end

  # Build stem load/mute instructions based on LLM stem preferences
  @spec build_stem_instructions(
          [%{track: Track.t(), analysis: AnalysisResult.t(), score: float()}],
          map()
        ) :: [Recipe.stem_instruction()]
  defp build_stem_instructions(selected_tracks, intent) do
    preferred_stems =
      (intent[:stem_preferences] || [])
      |> Enum.map(&normalise_stem_type/1)
      |> MapSet.new()

    # When no stem preference is given, default to loading all core stems
    all_core = MapSet.new([:vocals, :drums, :bass, :other])

    active_stems = if MapSet.size(preferred_stems) == 0, do: all_core, else: preferred_stems

    Enum.flat_map(selected_tracks, fn %{track: t} ->
      all_core
      |> Enum.map(fn stem_type ->
        action = if MapSet.member?(active_stems, stem_type), do: :load, else: :mute

        %{
          track_id: t.id,
          stem_type: stem_type,
          action: action
        }
      end)
    end)
  end

  @spec normalise_stem_type(String.t()) :: atom()
  defp normalise_stem_type(s) when is_binary(s) do
    s
    |> String.downcase()
    |> String.trim()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :other
  end

  defp normalise_stem_type(s) when is_atom(s), do: s
  defp normalise_stem_type(_), do: :other

  # Build human-readable mixing notes from the selected tracks and intent
  @spec generate_mixing_notes([map()], map()) :: String.t()
  defp generate_mixing_notes(tracks, intent) do
    track_count = length(tracks)
    curve = intent[:energy_curve] || "steady"

    tempo_range =
      tracks
      |> Enum.map(& &1.tempo)
      |> Enum.reject(&is_nil/1)

    {min_tempo, max_tempo} =
      case tempo_range do
        [] -> {nil, nil}
        tempos -> {Enum.min(tempos), Enum.max(tempos)}
      end

    tempo_note =
      if min_tempo && max_tempo do
        if min_tempo == max_tempo do
          "All tracks at #{Float.round(min_tempo, 1)} BPM."
        else
          "Tempo range: #{Float.round(min_tempo, 1)}-#{Float.round(max_tempo, 1)} BPM."
        end
      else
        "No tempo data available."
      end

    energy_note =
      case curve do
        "ascending" -> "Energy builds from low to high throughout the set."
        "descending" -> "Energy winds down from peak to chill."
        "peak" -> "Set builds to a peak in the middle then tapers."
        "wave" -> "Energy alternates in waves through the set."
        _ -> "Maintain a steady energy level."
      end

    """
    Chef Recipe -- #{track_count} tracks selected.
    #{tempo_note}
    #{energy_note}
    Tracks are alternated between Deck 1 and Deck 2 for crossfade mixing.
    Use the cue plan to mark mix-in points and drops for seamless transitions.\
    """
    |> String.trim()
  end
end
