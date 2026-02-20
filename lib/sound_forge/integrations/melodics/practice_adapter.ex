defmodule SoundForge.Integrations.Melodics.PracticeAdapter do
  @moduledoc """
  Adapts stem difficulty recommendations based on Melodics practice data.

  Maps Melodics instrument types to stem categories and suggests
  appropriate stem complexity based on user accuracy scores.
  """

  alias SoundForge.Integrations.Melodics

  @type difficulty :: :simple | :matched | :complex
  @type stem_category :: :vocals | :melody | :drums | :bass | :other

  # Melodics instrument -> SFA stem category mapping
  @instrument_map %{
    "pads" => :vocals,
    "pad" => :vocals,
    "keys" => :melody,
    "keyboard" => :melody,
    "piano" => :melody,
    "drums" => :drums,
    "drum" => :drums,
    "bass" => :bass,
    "guitar" => :other,
    "synth" => :melody
  }

  @doc """
  Suggest stems based on Melodics practice data for a user.

  Returns a list of {stem_category, difficulty} tuples.
  """
  @spec suggest_stems(String.t(), keyword()) :: [{stem_category(), difficulty()}]
  def suggest_stems(user_id, opts \\ []) do
    sessions = Melodics.list_sessions(user_id, limit: Keyword.get(opts, :limit, 100))

    sessions
    |> group_by_instrument()
    |> Enum.map(fn {instrument, instrument_sessions} ->
      category = map_instrument_to_category(instrument)
      avg_accuracy = average_accuracy(instrument_sessions)
      difficulty = difficulty_from_accuracy(avg_accuracy)
      {category, difficulty, %{avg_accuracy: avg_accuracy, session_count: length(instrument_sessions)}}
    end)
    |> Enum.sort_by(fn {_cat, _diff, meta} -> -meta.session_count end)
  end

  @doc "Map a Melodics instrument type to an SFA stem category."
  @spec map_instrument_to_category(String.t() | nil) :: stem_category()
  def map_instrument_to_category(nil), do: :other
  def map_instrument_to_category(instrument) do
    key = instrument |> String.downcase() |> String.trim()
    Map.get(@instrument_map, key, :other)
  end

  @doc "Determine difficulty level from accuracy percentage."
  @spec difficulty_from_accuracy(float() | nil) :: difficulty()
  def difficulty_from_accuracy(nil), do: :matched
  def difficulty_from_accuracy(accuracy) when accuracy < 60.0, do: :simple
  def difficulty_from_accuracy(accuracy) when accuracy > 85.0, do: :complex
  def difficulty_from_accuracy(_), do: :matched

  @doc "Get practice stats formatted for UI display."
  @spec practice_stats(String.t()) :: map()
  def practice_stats(user_id) do
    stats = Melodics.get_stats(user_id)
    suggestions = suggest_stems(user_id)

    Map.merge(stats, %{
      stem_suggestions: suggestions,
      strongest_category: strongest_category(suggestions),
      weakest_category: weakest_category(suggestions)
    })
  end

  # -- Private --

  defp group_by_instrument(sessions) do
    sessions
    |> Enum.group_by(fn s -> s.instrument || "other" end)
  end

  defp average_accuracy(sessions) do
    accuracies = sessions |> Enum.map(& &1.accuracy) |> Enum.reject(&is_nil/1)
    if accuracies == [], do: nil, else: Enum.sum(accuracies) / length(accuracies)
  end

  defp strongest_category(suggestions) do
    suggestions
    |> Enum.filter(fn {_cat, diff, _meta} -> diff == :complex end)
    |> List.first()
    |> case do
      {cat, _, _} -> cat
      nil -> nil
    end
  end

  defp weakest_category(suggestions) do
    suggestions
    |> Enum.filter(fn {_cat, diff, _meta} -> diff == :simple end)
    |> List.first()
    |> case do
      {cat, _, _} -> cat
      nil -> nil
    end
  end
end
