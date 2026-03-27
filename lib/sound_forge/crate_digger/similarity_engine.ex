defmodule SoundForge.CrateDigger.SimilarityEngine do
  @moduledoc """
  Audio similarity analysis for CrateDigger.

  ## Functions
    - `compute_crate_profile/1` — derive BPM cluster, key distribution, energy stats
      from the `AnalysisResult` records for all tracks in a crate.
    - `track_similarity/2` — pairwise similarity score (0.0–1.0) between two
      `AnalysisResult` structs based on BPM proximity, Camelot key compatibility,
      and energy delta.
    - `similarity_matrix/1` — NxN matrix for all tracks in a crate (for heatmap).

  ## Camelot Wheel
  Compatible keys are those adjacent on the Camelot wheel (same number, ±1 number,
  or the parallel major/minor for the same root).
  """

  import Ecto.Query, warn: false

  alias SoundForge.Music.{AnalysisResult, Track}
  alias SoundForge.CrateDigger.Crate
  alias SoundForge.Repo

  # Camelot wheel adjacency map: key -> list of compatible keys
  @camelot_adjacent %{
    "1A" => ~w(1A 2A 12A 1B),
    "2A" => ~w(2A 1A 3A 2B),
    "3A" => ~w(3A 2A 4A 3B),
    "4A" => ~w(4A 3A 5A 4B),
    "5A" => ~w(5A 4A 6A 5B),
    "6A" => ~w(6A 5A 7A 6B),
    "7A" => ~w(7A 6A 8A 7B),
    "8A" => ~w(8A 7A 9A 8B),
    "9A" => ~w(9A 8A 10A 9B),
    "10A" => ~w(10A 9A 11A 10B),
    "11A" => ~w(11A 10A 12A 11B),
    "12A" => ~w(12A 11A 1A 12B),
    "1B" => ~w(1B 2B 12B 1A),
    "2B" => ~w(2B 1B 3B 2A),
    "3B" => ~w(3B 2B 4B 3A),
    "4B" => ~w(4B 3B 5B 4A),
    "5B" => ~w(5B 4B 6B 5A),
    "6B" => ~w(6B 5B 7B 6A),
    "7B" => ~w(7B 6B 8B 7A),
    "8B" => ~w(8B 7B 9B 8A),
    "9B" => ~w(9B 8B 10B 9A),
    "10B" => ~w(10B 9B 11B 10A),
    "11B" => ~w(11B 10B 12B 11A),
    "12B" => ~w(12B 11B 1B 12A)
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Compute the crate-level audio profile from stored AnalysisResult records.

  Loads all tracks in the crate, queries their analysis results, then
  computes aggregate statistics. Returns `{:error, :insufficient_data}`
  if fewer than 2 tracks have analysis data.
  """
  @spec compute_crate_profile(Crate.t()) ::
          {:ok, map()} | {:error, :insufficient_data}
  def compute_crate_profile(%Crate{playlist_data: tracks}) when length(tracks) < 2 do
    {:error, :insufficient_data}
  end

  def compute_crate_profile(%Crate{playlist_data: playlist_data} = _crate) do
    spotify_ids =
      playlist_data
      |> Enum.map(& &1["spotify_id"])
      |> Enum.reject(&is_nil/1)

    analyses =
      from(a in AnalysisResult,
        join: t in Track,
        on: t.id == a.track_id,
        where: t.spotify_id in ^spotify_ids,
        select: a
      )
      |> Repo.all()

    if length(analyses) < 2 do
      {:error, :insufficient_data}
    else
      profile = build_profile(analyses)
      {:ok, profile}
    end
  end

  @doc """
  Compute pairwise similarity score between two AnalysisResult records.

  Returns a float 0.0–1.0 where 1.0 means highly compatible.
  """
  @spec track_similarity(AnalysisResult.t(), AnalysisResult.t()) :: float()
  def track_similarity(%AnalysisResult{} = a, %AnalysisResult{} = b) do
    bpm_score = bpm_similarity(a.tempo, b.tempo)
    key_score = key_similarity(a.key, b.key)
    energy_score = energy_similarity(a.energy, b.energy)

    # Weighted: BPM 40%, key 35%, energy 25%
    bpm_score * 0.40 + key_score * 0.35 + energy_score * 0.25
  end

  @doc """
  Compute an NxN similarity matrix for all analysis-loaded tracks in a crate.

  Returns `{:ok, {names, matrix}}` where:
    - `names` is a list of track title strings (N elements)
    - `matrix` is a list-of-lists of floats (N x N)
  """
  @spec similarity_matrix(Crate.t()) ::
          {:ok, {[String.t()], [[float()]]}} | {:error, :insufficient_data}
  def similarity_matrix(%Crate{playlist_data: playlist_data}) do
    spotify_ids = Enum.map(playlist_data, & &1["spotify_id"]) |> Enum.reject(&is_nil/1)

    tracks_with_analysis =
      from(a in AnalysisResult,
        join: t in Track,
        on: t.id == a.track_id,
        where: t.spotify_id in ^spotify_ids,
        select: {t.title, t.spotify_id, a}
      )
      |> Repo.all()

    if length(tracks_with_analysis) < 2 do
      {:error, :insufficient_data}
    else
      names = Enum.map(tracks_with_analysis, fn {title, _, _} -> title || "?" end)
      analyses = Enum.map(tracks_with_analysis, fn {_, _, a} -> a end)

      matrix =
        Enum.map(analyses, fn a ->
          Enum.map(analyses, fn b -> track_similarity(a, b) end)
        end)

      {:ok, {names, matrix}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: profile builder
  # ---------------------------------------------------------------------------

  defp build_profile(analyses) do
    tempos = analyses |> Enum.map(& &1.tempo) |> Enum.reject(&is_nil/1)
    energies = analyses |> Enum.map(& &1.energy) |> Enum.reject(&is_nil/1)
    keys = analyses |> Enum.map(& &1.key) |> Enum.reject(&is_nil/1)

    bpm_center = if Enum.empty?(tempos), do: nil, else: median(tempos)
    bpm_stddev = if length(tempos) < 2, do: nil, else: stddev(tempos)

    energy_mean = if Enum.empty?(energies), do: nil, else: mean(energies)

    energy_range =
      if Enum.empty?(energies),
        do: nil,
        else: [Float.round(Enum.min(energies), 3), Float.round(Enum.max(energies), 3)]

    top_keys =
      keys
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_k, v} -> -v end)
      |> Enum.take(3)
      |> Enum.map(fn {k, _} -> k end)

    %{
      "bpm_center" => bpm_center && Float.round(bpm_center * 1.0, 1),
      "bpm_stddev" => bpm_stddev && Float.round(bpm_stddev * 1.0, 2),
      "top_keys" => top_keys,
      "energy_mean" => energy_mean && Float.round(energy_mean * 1.0, 3),
      "energy_range" => energy_range,
      "analyzed_count" => length(analyses),
      "mode" => "auto"
    }
  end

  # ---------------------------------------------------------------------------
  # Private: similarity sub-scores
  # ---------------------------------------------------------------------------

  defp bpm_similarity(nil, _), do: 0.5
  defp bpm_similarity(_, nil), do: 0.5

  defp bpm_similarity(a, b) do
    diff = abs(a - b)
    # Within 2 BPM: perfect. Within 6: good. Beyond 12: low.
    cond do
      diff <= 2.0 -> 1.0
      diff <= 6.0 -> 1.0 - (diff - 2.0) / 8.0
      diff <= 12.0 -> 0.5 - (diff - 6.0) / 20.0
      true -> max(0.0, 0.2 - (diff - 12.0) / 60.0)
    end
  end

  defp key_similarity(nil, _), do: 0.5
  defp key_similarity(_, nil), do: 0.5

  defp key_similarity(a, b) when a == b, do: 1.0

  defp key_similarity(a, b) do
    adjacent = Map.get(@camelot_adjacent, a, [])
    if b in adjacent, do: 0.8, else: 0.1
  end

  defp energy_similarity(nil, _), do: 0.5
  defp energy_similarity(_, nil), do: 0.5

  defp energy_similarity(a, b) do
    diff = abs(a - b)
    max(0.0, 1.0 - diff * 3.0)
  end

  # ---------------------------------------------------------------------------
  # Private: statistics helpers
  # ---------------------------------------------------------------------------

  defp mean([]), do: 0.0
  defp mean(list), do: Enum.sum(list) / length(list)

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)

    if rem(n, 2) == 0 do
      (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2.0
    else
      Enum.at(sorted, div(n, 2))
    end
  end

  defp stddev(list) do
    m = mean(list)
    variance = list |> Enum.map(fn x -> (x - m) ** 2 end) |> mean()
    :math.sqrt(variance)
  end
end
