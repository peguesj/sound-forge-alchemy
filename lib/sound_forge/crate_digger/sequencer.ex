defmodule SoundForge.CrateDigger.Sequencer do
  @moduledoc """
  Smart sequencer for CrateDigger.

  Given a crate and a target energy arc, reorders tracks for optimal mix flow
  using similarity scores and energy progression data.

  ## Arc types
    - `:rise`  — low → high energy build
    - `:fall`  — high → low energy wind-down
    - `:peak`  — low → high → low (arc shape)
    - `:flat`  — minimal energy variance, smooth/consistent

  When insufficient analysis data exists, falls back to BPM-sorted order.
  """

  import Ecto.Query, warn: false

  alias SoundForge.CrateDigger.Crate
  alias SoundForge.CrateDigger.SimilarityEngine
  alias SoundForge.Music.{AnalysisResult, Track}
  alias SoundForge.Repo

  @type arc_type :: :rise | :fall | :peak | :flat

  @doc """
  Sequence tracks in a crate according to the given energy arc.

  Returns `{:ok, [track_map]}` where each track_map is the original playlist_data
  entry enriched with `"_bpm_delta"` and `"_key_compat"` metadata for UI display.
  """
  @spec sequence(Crate.t(), arc_type()) :: {:ok, [map()]} | {:error, term()}
  def sequence(%Crate{playlist_data: []}, _arc), do: {:ok, []}

  def sequence(%Crate{playlist_data: tracks} = crate, arc) do
    # Load analysis results for crate tracks
    spotify_ids = Enum.map(tracks, & &1["spotify_id"]) |> Enum.reject(&is_nil/1)

    analyses_by_spotify_id =
      from(a in AnalysisResult,
        join: t in Track,
        on: t.id == a.track_id,
        where: t.spotify_id in ^spotify_ids,
        select: {t.spotify_id, a}
      )
      |> Repo.all()
      |> Map.new()

    if map_size(analyses_by_spotify_id) < 2 do
      # Fallback: BPM-sorted
      sorted = Enum.sort_by(tracks, fn t ->
        analysis = Map.get(analyses_by_spotify_id, t["spotify_id"])
        analysis && analysis.tempo || 999
      end)

      {:ok, annotate_sequence(sorted, analyses_by_spotify_id)}
    else
      ordered = order_by_arc(tracks, analyses_by_spotify_id, arc)
      {:ok, annotate_sequence(ordered, analyses_by_spotify_id)}
    end
  end

  # ---------------------------------------------------------------------------
  # Arc ordering algorithms
  # ---------------------------------------------------------------------------

  defp order_by_arc(tracks, analyses, :rise) do
    Enum.sort_by(tracks, fn t ->
      analysis = Map.get(analyses, t["spotify_id"])
      energy = (analysis && analysis.energy) || 0.5
      energy
    end)
  end

  defp order_by_arc(tracks, analyses, :fall) do
    Enum.sort_by(tracks, fn t ->
      analysis = Map.get(analyses, t["spotify_id"])
      energy = (analysis && analysis.energy) || 0.5
      -energy
    end)
  end

  defp order_by_arc(tracks, analyses, :peak) do
    # Sort by energy ascending, then split into halves and reverse second half
    sorted_rise = order_by_arc(tracks, analyses, :rise)
    n = length(sorted_rise)
    mid = div(n, 2)
    {first_half, second_half} = Enum.split(sorted_rise, mid)
    first_half ++ Enum.reverse(second_half)
  end

  defp order_by_arc(tracks, analyses, :flat) do
    # Minimize adjacent energy delta using a greedy nearest-neighbor approach
    if Enum.empty?(tracks) do
      tracks
    else
      energies = Map.new(tracks, fn t ->
        analysis = Map.get(analyses, t["spotify_id"])
        {t["spotify_id"], (analysis && analysis.energy) || 0.5}
      end)

      mean_energy = energies |> Map.values() |> then(fn vals -> Enum.sum(vals) / length(vals) end)

      # Start with track closest to mean
      [first | rest] =
        Enum.sort_by(tracks, fn t ->
          abs(Map.get(energies, t["spotify_id"], 0.5) - mean_energy)
        end)

      greedy_sort([first], rest, energies)
    end
  end

  defp greedy_sort(ordered, [], _energies), do: ordered

  defp greedy_sort(ordered, remaining, energies) do
    last = List.last(ordered)
    last_energy = Map.get(energies, last["spotify_id"], 0.5)

    next =
      Enum.min_by(remaining, fn t ->
        abs(Map.get(energies, t["spotify_id"], 0.5) - last_energy)
      end)

    greedy_sort(ordered ++ [next], List.delete(remaining, next), energies)
  end

  # ---------------------------------------------------------------------------
  # Annotation
  # ---------------------------------------------------------------------------

  defp annotate_sequence(tracks, analyses) do
    tracks
    |> Enum.with_index()
    |> Enum.map(fn {track, idx} ->
      analysis = Map.get(analyses, track["spotify_id"])
      prev = idx > 0 && Enum.at(tracks, idx - 1)
      prev_analysis = prev && Map.get(analyses, prev["spotify_id"])

      bpm_delta =
        if analysis && prev_analysis && analysis.tempo && prev_analysis.tempo do
          round(analysis.tempo - prev_analysis.tempo)
        end

      key_compat =
        if analysis && prev_analysis && analysis.key && prev_analysis.key do
          score = SimilarityEngine.track_similarity(analysis, prev_analysis)
          cond do
            score > 0.8 -> "compatible"
            score > 0.5 -> "close"
            true -> "distant"
          end
        end

      track
      |> Map.put("_bpm_delta", bpm_delta)
      |> Map.put("_key_compat", key_compat)
      |> Map.put("_energy", analysis && analysis.energy)
    end)
  end
end
