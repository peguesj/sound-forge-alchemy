defmodule SoundForge.BigLoopy do
  @moduledoc """
  The BigLoopy context.

  Manages AlchemySets — the unified data model for BigLoopy's loop-based
  alchemy pipeline. Users select source tracks, describe a recipe in natural
  language, and the pipeline assembles extracted loops into a downloadable set.
  """

  import Ecto.Query, warn: false
  require Logger

  alias SoundForge.Repo
  alias SoundForge.BigLoopy.AlchemySet

  # ---------------------------------------------------------------------------
  # AlchemySet CRUD
  # ---------------------------------------------------------------------------

  @doc "Lists all AlchemySets for a given user, ordered by most recently created."
  @spec list_alchemy_sets(integer()) :: [AlchemySet.t()]
  def list_alchemy_sets(user_id) do
    AlchemySet
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc "Gets a single AlchemySet by id. Returns nil if not found."
  @spec get_alchemy_set(binary()) :: AlchemySet.t() | nil
  def get_alchemy_set(id) do
    Repo.get(AlchemySet, id)
  end

  @doc "Creates an AlchemySet."
  @spec create_alchemy_set(map()) :: {:ok, AlchemySet.t()} | {:error, Ecto.Changeset.t()}
  def create_alchemy_set(attrs \\ %{}) do
    %AlchemySet{}
    |> AlchemySet.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an AlchemySet."
  @spec update_alchemy_set(AlchemySet.t(), map()) :: {:ok, AlchemySet.t()} | {:error, Ecto.Changeset.t()}
  def update_alchemy_set(%AlchemySet{} = alchemy_set, attrs) do
    alchemy_set
    |> AlchemySet.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes an AlchemySet."
  @spec delete_alchemy_set(AlchemySet.t()) :: {:ok, AlchemySet.t()} | {:error, Ecto.Changeset.t()}
  def delete_alchemy_set(%AlchemySet{} = alchemy_set) do
    Repo.delete(alchemy_set)
  end

  # ---------------------------------------------------------------------------
  # PerformanceSet helpers
  # ---------------------------------------------------------------------------

  @doc """
  Saves a performance set layout to an AlchemySet.

  The performance_set map is a free-form structure keyed by pad slot:
      %{
        "pad_0" => %{"loop_path" => "/path/to/loop.wav", "label" => "Kick", "stem" => "drums"},
        ...
      }
  """
  @spec save_performance_set(AlchemySet.t(), map()) ::
          {:ok, AlchemySet.t()} | {:error, Ecto.Changeset.t()}
  def save_performance_set(%AlchemySet{} = alchemy_set, performance_set) do
    update_alchemy_set(alchemy_set, %{performance_set: performance_set})
  end

  @doc "Loads the performance set from an AlchemySet by id."
  @spec load_performance_set(binary()) :: {:ok, map()} | {:error, :not_found}
  def load_performance_set(alchemy_set_id) do
    case get_alchemy_set(alchemy_set_id) do
      nil -> {:error, :not_found}
      %AlchemySet{performance_set: ps} -> {:ok, ps}
    end
  end

  # ---------------------------------------------------------------------------
  # Status helpers
  # ---------------------------------------------------------------------------

  @doc "Updates only the status field of an AlchemySet."
  @spec update_status(AlchemySet.t(), String.t()) ::
          {:ok, AlchemySet.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%AlchemySet{} = alchemy_set, status)
      when status in ~w(pending processing complete error) do
    update_alchemy_set(alchemy_set, %{status: status})
  end
end
