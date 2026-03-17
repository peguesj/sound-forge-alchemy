defmodule SoundForge.BigLoopy.OmegaChop do
  @moduledoc """
  OmegaChop — AI-assisted stem routing for BigLoopy.

  Analyzes a track's stored analysis data and a recipe configuration to
  determine which stems should be used for each loop slot in an AlchemySet.

  Returns a stem_assignments map keyed by loop slot index:
      %{0 => "drums", 1 => "bass", 2 => "other", 3 => "vocals"}
  """

  require Logger

  @stem_types ~w(vocals drums bass other guitar piano)

  @doc """
  Assigns stems to loop slots based on track analysis data and recipe config.

  `analysis` is the track's stored analysis map (from SoundForge.Tracks.get_track/1,
  field: `:analysis_data`).

  `recipe` is a map that may contain:
    - `"stems"` — list of stem names to prefer (overrides auto-detection)
    - `"loop_count"` — number of loop slots to fill (default: 4)
    - `"primary_stem"` — the stem to use for slot 0

  Returns `%{slot_index => stem_type}` map.
  """
  @spec assign_stems(map(), map()) :: %{non_neg_integer() => String.t()}
  def assign_stems(analysis, recipe \\ %{}) do
    loop_count = Map.get(recipe, "loop_count", 4)
    preferred_stems = Map.get(recipe, "stems", [])
    primary_stem = Map.get(recipe, "primary_stem", nil)

    stems_to_assign =
      cond do
        length(preferred_stems) >= loop_count ->
          Enum.take(preferred_stems, loop_count)

        primary_stem != nil ->
          [primary_stem | pick_supporting_stems(analysis, loop_count - 1, [primary_stem])]

        true ->
          auto_assign_from_analysis(analysis, loop_count)
      end

    stems_to_assign
    |> Enum.with_index()
    |> Enum.into(%{}, fn {stem, idx} -> {idx, stem} end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp auto_assign_from_analysis(analysis, count) do
    # Prefer stems with higher energy/presence based on analysis data
    dominant = dominant_stem(analysis)
    supporting = pick_supporting_stems(analysis, count - 1, [dominant])
    [dominant | supporting]
  end

  defp dominant_stem(analysis) when is_map(analysis) do
    # Use stem_energies from analysis if available
    energies = Map.get(analysis, "stem_energies", %{})

    if map_size(energies) > 0 do
      {stem, _energy} = Enum.max_by(energies, fn {_k, v} -> v end, fn -> {"drums", 0.0} end)
      if stem in @stem_types, do: stem, else: "drums"
    else
      "drums"
    end
  end

  defp dominant_stem(_), do: "drums"

  defp pick_supporting_stems(_analysis, 0, _exclude), do: []

  defp pick_supporting_stems(analysis, count, exclude) do
    energies = Map.get(analysis || %{}, "stem_energies", %{})

    candidates =
      @stem_types
      |> Enum.reject(&(&1 in exclude))
      |> Enum.sort_by(fn stem ->
        -(Map.get(energies, stem, 0.0))
      end)
      |> Enum.take(count)

    # Pad with "other" if not enough candidates
    padding = List.duplicate("other", max(0, count - length(candidates)))
    candidates ++ padding
  end
end
