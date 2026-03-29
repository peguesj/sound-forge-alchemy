defmodule SoundForge.DAW.TrackClassifier do
  @moduledoc """
  Classifies audio tracks by type based on duration, BPM, and title/filename keywords.

  Supported types:
    - `:full_track`   — full-length song (>= 30 seconds)
    - `:loop`         — short repeating segment without drum indicators
    - `:drum_loop`    — short percussive loop (kick, snare, hat, etc.)
    - `:sample_loop`  — very short sample (< 8 seconds)
    - `:unknown`      — not enough information to classify

  Classification priority:
    1. `classify_from_analysis/2` when an `AnalysisResult` or BPM is present on the track
    2. `classify_from_filename/1` based on title keywords
    3. `{:unknown, 0.0}` fallback
  """

  alias SoundForge.Music.Track

  @drum_keywords ~w(kick snare drum beat loop trap hat clap)
  @loop_keywords ~w(loop sample stem)

  # ──────────────────────────────────────────────────────────────────────────────
  # Public API
  # ──────────────────────────────────────────────────────────────────────────────

  @doc """
  Classify a single track.

  Accepts a `%Track{}` struct with an optionally preloaded `:analysis_results` association.
  Returns `{:ok, type_atom, confidence_float}`.
  """
  @spec classify(Track.t()) :: {:ok, atom(), float()}
  def classify(%Track{} = track) do
    {type, confidence} =
      case best_analysis_result(track) do
        nil ->
          classify_from_filename(track)

        analysis_result ->
          case classify_from_analysis(track, analysis_result) do
            {:unknown, _} -> classify_from_filename(track)
            result -> result
          end
      end

    {:ok, type, confidence}
  end

  @doc """
  Classify a list of tracks.

  Returns a list of `{track_id, type_atom, confidence_float}` tuples.
  """
  @spec classify_batch([Track.t()]) :: [{binary(), atom(), float()}]
  def classify_batch(tracks) when is_list(tracks) do
    Enum.map(tracks, fn track ->
      {:ok, type, confidence} = classify(track)
      {track.id, type, confidence}
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────────

  # Pick the first loaded AnalysisResult if the association has been preloaded,
  # otherwise return nil.
  defp best_analysis_result(%Track{analysis_results: results})
       when is_list(results) and results != [] do
    List.first(results)
  end

  defp best_analysis_result(_track), do: nil

  # Classify using duration (from track) and BPM (from track.bpm or analysis_result.tempo).
  defp classify_from_analysis(%Track{} = track, analysis_result) do
    duration_sec = resolve_duration_sec(track)
    bpm = resolve_bpm(track, analysis_result)

    cond do
      is_nil(duration_sec) ->
        {:unknown, 0.0}

      duration_sec < 8.0 ->
        {:sample_loop, 0.9}

      duration_sec < 30.0 and not is_nil(bpm) and bpm > 0 ->
        if drum_keywords_in_title?(track.title) do
          {:drum_loop, 0.85}
        else
          {:loop, 0.80}
        end

      duration_sec >= 30.0 ->
        {:full_track, 0.85}

      true ->
        {:unknown, 0.0}
    end
  end

  # Classify based solely on title keywords and any duration clue in the title.
  defp classify_from_filename(%Track{} = track) do
    title = normalize(track.title)

    cond do
      drum_keywords_in_title?(title) ->
        {:drum_loop, 0.6}

      loop_keywords_in_title?(title) ->
        {:loop, 0.5}

      has_duration_hint_in_title?(title) ->
        {:full_track, 0.5}

      true ->
        {:unknown, 0.3}
    end
  end

  # Return duration in seconds. Prefer duration_ms (milliseconds) on the track,
  # fall back to duration (seconds, as stored by Spotify metadata).
  defp resolve_duration_sec(%Track{duration_ms: ms}) when is_integer(ms) and ms > 0 do
    ms / 1000.0
  end

  defp resolve_duration_sec(%Track{duration: secs}) when is_integer(secs) and secs > 0 do
    secs * 1.0
  end

  defp resolve_duration_sec(_track), do: nil

  # Return BPM: prefer the track-level field, then the analysis tempo.
  defp resolve_bpm(%Track{bpm: bpm}, _analysis_result) when is_float(bpm) and bpm > 0,
    do: bpm

  defp resolve_bpm(_track, %{tempo: tempo}) when is_float(tempo) and tempo > 0, do: tempo
  defp resolve_bpm(_track, _analysis_result), do: nil

  defp drum_keywords_in_title?(nil), do: false

  defp drum_keywords_in_title?(title) do
    t = normalize(title)
    Enum.any?(@drum_keywords, &String.contains?(t, &1))
  end

  defp loop_keywords_in_title?(nil), do: false

  defp loop_keywords_in_title?(title) do
    t = normalize(title)
    Enum.any?(@loop_keywords, &String.contains?(t, &1))
  end

  # Detect patterns like "2:30", "3:04", or numbers > 60 that imply song duration.
  defp has_duration_hint_in_title?(nil), do: false

  defp has_duration_hint_in_title?(title) do
    String.match?(title, ~r/\d+:\d{2}/)
  end

  defp normalize(nil), do: ""
  defp normalize(str), do: String.downcase(str)
end
