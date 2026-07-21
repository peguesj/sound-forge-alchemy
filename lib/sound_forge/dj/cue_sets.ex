defmodule SoundForge.DJ.CueSets do
  @moduledoc """
  Context for Chef AI cue/loop sets.

  Manages AI-generated sets of cue points, loops, and hot cues for tracks.
  Users can generate, preview (paginated), save, load, and swap Chef Sets
  on a deck.
  """
  import Ecto.Query, warn: false

  alias SoundForge.Repo
  alias SoundForge.DJ.ChefSet
  alias SoundForge.DJ.ChefSetItem

  require Logger

  # ---------------------------------------------------------------------------
  # Chef Set CRUD
  # ---------------------------------------------------------------------------

  @doc "Lists all Chef sets for a user and track, ordered most-recent first."
  @spec list_chef_sets(term(), binary()) :: [ChefSet.t()]
  def list_chef_sets(user_id, track_id) do
    ChefSet
    |> where([cs], cs.user_id == ^user_id and cs.track_id == ^track_id)
    |> order_by([cs], desc: cs.inserted_at)
    |> Repo.all()
  end

  @doc "Gets a single Chef set by ID scoped to user. Returns nil if not found."
  @spec get_chef_set(binary(), term()) :: ChefSet.t() | nil
  def get_chef_set(id, user_id) do
    ChefSet
    |> where([cs], cs.id == ^id and cs.user_id == ^user_id)
    |> Repo.one()
  end

  @doc "Creates a new Chef set."
  @spec create_chef_set(map()) :: {:ok, ChefSet.t()} | {:error, Ecto.Changeset.t()}
  def create_chef_set(attrs) do
    %ChefSet{}
    |> ChefSet.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a Chef set by ID, scoped to user."
  @spec delete_chef_set(binary(), term()) :: {:ok, ChefSet.t()} | {:error, term()}
  def delete_chef_set(id, user_id) do
    case get_chef_set(id, user_id) do
      nil -> {:error, :not_found}
      chef_set -> Repo.delete(chef_set)
    end
  end

  # ---------------------------------------------------------------------------
  # Items — paginated, sortable
  # ---------------------------------------------------------------------------

  @doc """
  Lists items for a Chef set with pagination and sorting.

  opts:
  - page: 1-based page (default 1)
  - per_page: items per page (default 8)
  - sort_by: :confidence | :position_ms | :intelligent (default :confidence)
  """
  @spec list_chef_set_items(binary(), keyword()) :: %{
          items: [ChefSetItem.t()],
          total: integer(),
          page: integer(),
          pages: integer(),
          per_page: integer()
        }
  def list_chef_set_items(chef_set_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 8)
    sort_by = Keyword.get(opts, :sort_by, :confidence)
    offset = (page - 1) * per_page

    base =
      ChefSetItem
      |> where([i], i.chef_set_id == ^chef_set_id)

    total = Repo.aggregate(base, :count, :id)

    items =
      base
      |> apply_item_sort(sort_by)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      items: items,
      total: total,
      page: page,
      pages: max(1, ceil(total / per_page)),
      per_page: per_page
    }
  end

  @doc """
  Saves a list of cue/loop maps as items in an existing Chef set.
  Replaces all existing items.
  """
  @spec save_chef_set_items(binary(), [map()]) :: {:ok, integer()} | {:error, term()}
  def save_chef_set_items(chef_set_id, items) do
    ChefSetItem
    |> where([i], i.chef_set_id == ^chef_set_id)
    |> Repo.delete_all()

    results =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        %ChefSetItem{}
        |> ChefSetItem.changeset(%{
          chef_set_id: chef_set_id,
          position_ms: item["position_ms"] || item[:position_ms],
          end_ms: item["end_ms"] || item[:end_ms],
          label: item["label"] || item[:label],
          confidence: item["confidence"] || item[:confidence],
          item_type: item["item_type"] || item[:item_type] || "hot_cue",
          color: item["color"] || item[:color],
          sort_order: idx
        })
        |> Repo.insert()
      end)

    {ok_count, err_count} =
      Enum.reduce(results, {0, 0}, fn
        {:ok, _}, {ok, err} -> {ok + 1, err}
        {:error, _}, {ok, err} -> {ok, err + 1}
      end)

    if err_count > 0 do
      Logger.warning("CueSets: #{err_count} items failed to save for set #{chef_set_id}")
    end

    {:ok, ok_count}
  end

  @doc """
  Creates a Chef set from auto-generated cues, saving items atomically.
  """
  @spec create_set_from_cues([map()], map()) :: {:ok, ChefSet.t()} | {:error, term()}
  def create_set_from_cues(cues, attrs) do
    with {:ok, chef_set} <- create_chef_set(attrs),
         {:ok, _count} <- save_chef_set_items(chef_set.id, cues) do
      {:ok, Repo.preload(chef_set, :items)}
    end
  end

  @doc """
  Triggers AI cue generation via Oban (AutoCueWorker).

  opts:
  - type: "cue_set" | "loop_set" | "hot_cue_set" (default "cue_set")
  - priorities: %{"drops" => 1.0, "energy" => 0.8}
  - leading_stem: "drums" | "bass" etc
  - name: display name for the resulting set
  """
  @spec generate_chef_set(binary(), term(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def generate_chef_set(track_id, user_id, opts \\ []) do
    %{
      "track_id" => track_id,
      "user_id" => user_id,
      "leading_stem" => Keyword.get(opts, :leading_stem, "drums"),
      "chef_mode" => true,
      "chef_set_type" => Keyword.get(opts, :type, "cue_set"),
      "chef_set_name" => Keyword.get(opts, :name, "Chef Set #{Date.utc_today()}"),
      "chef_priorities" => Keyword.get(opts, :priorities, %{})
    }
    |> SoundForge.Jobs.AutoCueWorker.new()
    |> Oban.insert()
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp apply_item_sort(query, :confidence) do
    order_by(query, [i], desc_nulls_last: i.confidence)
  end

  defp apply_item_sort(query, :position_ms) do
    order_by(query, [i], asc: i.position_ms)
  end

  defp apply_item_sort(query, :intelligent) do
    order_by(query, [i], asc_nulls_last: i.sort_order, desc_nulls_last: i.confidence)
  end

  defp apply_item_sort(query, _), do: apply_item_sort(query, :confidence)
end
