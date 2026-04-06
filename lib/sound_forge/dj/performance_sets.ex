defmodule SoundForge.DJ.PerformanceSets do
  @moduledoc """
  Context for PerformanceSet CRUD and factory helpers.
  """

  import Ecto.Query, warn: false

  alias SoundForge.DJ.PerformanceSet
  alias SoundForge.Repo

  @doc "Create a PerformanceSet."
  @spec create(map()) :: {:ok, PerformanceSet.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %PerformanceSet{}
    |> PerformanceSet.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List all PerformanceSets for a user, newest first."
  @spec list_for_user(integer()) :: [PerformanceSet.t()]
  def list_for_user(user_id) do
    PerformanceSet
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "List PerformanceSets for a user and track."
  @spec list_for_track(integer(), binary()) :: [PerformanceSet.t()]
  def list_for_track(user_id, track_id) do
    PerformanceSet
    |> where([p], p.user_id == ^user_id and p.track_id == ^track_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc "Get a single PerformanceSet by ID. Returns nil if not found."
  @spec get(binary()) :: PerformanceSet.t() | nil
  def get(id) do
    Repo.get(PerformanceSet, id)
  end

  @doc "Delete a PerformanceSet."
  @spec delete(PerformanceSet.t()) :: {:ok, PerformanceSet.t()} | {:error, Ecto.Changeset.t()}
  def delete(%PerformanceSet{} = set), do: Repo.delete(set)

  @doc """
  Mark a PerformanceSet as activated (sets `activated_at` to now).
  """
  @spec mark_activated(PerformanceSet.t()) ::
          {:ok, PerformanceSet.t()} | {:error, Ecto.Changeset.t()}
  def mark_activated(%PerformanceSet{} = set) do
    set
    |> PerformanceSet.changeset(%{activated_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  @doc """
  Build a PerformanceSet from a finalized Chef recipe and persist it.

  Converts the recipe's tracks and cue_plan into PerformanceSetItems stored as JSONB.
  Returns `{:ok, performance_set}` on success.
  """
  @spec from_chef_recipe(map(), integer()) ::
          {:ok, PerformanceSet.t()} | {:error, term()}
  def from_chef_recipe(finalized_recipe, user_id) do
    tracks = finalized_recipe[:tracks] || []
    cue_plan = finalized_recipe[:cue_plan] || []
    recipe_meta = finalized_recipe[:recipe_meta] || %{}

    set_name =
      recipe_meta[:prompt] || recipe_meta["prompt"] ||
        "Chef Set #{length(tracks)} Tracks"

    items =
      tracks
      |> Enum.with_index()
      |> Enum.flat_map(fn {track, sort_order} ->
        track_id = track[:track_id] || track["track_id"]
        title = track[:title] || track["title"] || "Track #{sort_order + 1}"

        # Look for cue plan entries for this track
        track_cues =
          cue_plan
          |> Enum.filter(fn c ->
            (c[:track_id] || c["track_id"]) == track_id
          end)
          |> Enum.map(fn cue ->
            %{
              "position_ms" => cue[:position_ms] || cue["position_ms"] || 0,
              "end_ms" => cue[:end_ms] || cue["end_ms"],
              "label" => cue[:label] || cue["label"] || title,
              "item_type" => cue[:type] || cue["type"] || "cue",
              "color" => cue[:color] || cue["color"] || "#a855f7",
              "sort_order" => sort_order,
              "confidence" => cue[:confidence] || cue["confidence"] || 0.8
            }
          end)

        if Enum.empty?(track_cues) do
          # No cues from plan — create a simple marker at position 0
          [
            %{
              "position_ms" => 0,
              "label" => title,
              "item_type" => "marker",
              "color" => "#a855f7",
              "sort_order" => sort_order,
              "confidence" => 0.7
            }
          ]
        else
          track_cues
        end
      end)

    attrs = %{
      name: set_name,
      set_type: "cueset",
      source: "chef",
      schema_version: "1.0",
      items: items,
      metadata: %{
        "track_count" => length(tracks),
        "prompt" => recipe_meta[:prompt] || recipe_meta["prompt"],
        "completed_at" => finalized_recipe[:completed_at] || finalized_recipe["completed_at"]
      },
      generation_opts: recipe_meta,
      user_id: user_id
    }

    create(attrs)
  end
end
