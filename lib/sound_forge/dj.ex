defmodule SoundForge.DJ do
  @moduledoc """
  The DJ context.

  Manages cue points, deck sessions, and stem loops for DJ workflow,
  including hot cues, loop markers, deck state, track loading, and
  per-stem loop regions.
  """

  import Ecto.Query, warn: false
  alias SoundForge.Repo

  alias SoundForge.DJ.CuePoint
  alias SoundForge.DJ.DeckSession
  alias SoundForge.DJ.StemLoop

  # ---------------------------------------------------------------------------
  # Cue Point functions
  # ---------------------------------------------------------------------------

  @doc """
  Creates a cue point.

  ## Examples

      iex> create_cue_point(%{track_id: id, user_id: uid, position_ms: 30000, cue_type: :hot})
      {:ok, %CuePoint{}}

  """
  @spec create_cue_point(map()) :: {:ok, CuePoint.t()} | {:error, Ecto.Changeset.t()}
  def create_cue_point(attrs \\ %{}) do
    %CuePoint{}
    |> CuePoint.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all cue points for a track belonging to a specific user,
  ordered by position_ms ascending.
  """
  @spec list_cue_points(binary(), term()) :: [CuePoint.t()]
  def list_cue_points(track_id, user_id) do
    CuePoint
    |> where([cp], cp.track_id == ^track_id and cp.user_id == ^user_id)
    |> order_by([cp], asc: cp.position_ms)
    |> Repo.all()
  end

  @doc """
  Updates a cue point.

  ## Examples

      iex> update_cue_point(cue_point, %{label: "Drop"})
      {:ok, %CuePoint{}}

  """
  @spec update_cue_point(CuePoint.t(), map()) ::
          {:ok, CuePoint.t()} | {:error, Ecto.Changeset.t()}
  def update_cue_point(%CuePoint{} = cue_point, attrs) do
    cue_point
    |> CuePoint.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a single cue point by ID.

  Returns `nil` if the cue point does not exist.

  ## Examples

      iex> get_cue_point("some-uuid")
      %CuePoint{}

      iex> get_cue_point("nonexistent")
      nil

  """
  @spec get_cue_point(binary()) :: CuePoint.t() | nil
  def get_cue_point(id), do: Repo.get(CuePoint, id)

  @doc """
  Deletes a cue point.

  ## Examples

      iex> delete_cue_point(cue_point)
      {:ok, %CuePoint{}}

  """
  @spec delete_cue_point(CuePoint.t()) :: {:ok, CuePoint.t()} | {:error, Ecto.Changeset.t()}
  def delete_cue_point(%CuePoint{} = cue_point) do
    Repo.delete(cue_point)
  end

  @doc """
  Enqueues an Oban job to generate automatic cue points for a track.

  The AutoCueWorker will analyze the audio, detect arrangement markers
  (drops, build-ups, key changes, energy transitions, section boundaries),
  and persist them as cue points with `auto_generated: true`.

  ## Examples

      iex> generate_auto_cues(track_id, user_id)
      {:ok, %Oban.Job{}}

  """
  @spec generate_auto_cues(binary(), integer() | binary()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def generate_auto_cues(track_id, user_id) do
    %{"track_id" => track_id, "user_id" => user_id}
    |> SoundForge.Jobs.AutoCueWorker.new()
    |> Oban.insert()
  end

  @doc """
  Lists all auto-generated cue points for a track belonging to a specific user,
  ordered by position_ms ascending.
  """
  @spec list_auto_cue_points(binary(), term()) :: [CuePoint.t()]
  def list_auto_cue_points(track_id, user_id) do
    CuePoint
    |> where([cp],
      cp.track_id == ^track_id and cp.user_id == ^user_id and cp.auto_generated == true
    )
    |> order_by([cp], asc: cp.position_ms)
    |> Repo.all()
  end

  @doc """
  Deletes all auto-generated cue points for a track belonging to a specific user.

  Returns the count of deleted records.

  ## Examples

      iex> delete_auto_cue_points(track_id, user_id)
      {3, nil}

  """
  @spec delete_auto_cue_points(binary(), term()) :: {non_neg_integer(), nil | [term()]}
  def delete_auto_cue_points(track_id, user_id) do
    CuePoint
    |> where([cp],
      cp.track_id == ^track_id and cp.user_id == ^user_id and cp.auto_generated == true
    )
    |> Repo.delete_all()
  end

  # ---------------------------------------------------------------------------
  # Deck Session functions
  # ---------------------------------------------------------------------------

  @doc """
  Gets an existing deck session for the given user and deck number,
  or creates a new one. When `track_id` is provided the new session
  is initialised with that track loaded.

  ## Examples

      iex> get_or_create_deck_session(user_id, 1)
      {:ok, %DeckSession{}}

      iex> get_or_create_deck_session(user_id, 2, track_id)
      {:ok, %DeckSession{}}

  """
  @spec get_or_create_deck_session(term(), integer(), binary() | nil) ::
          {:ok, DeckSession.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_deck_session(user_id, deck_number, track_id \\ nil) do
    case Repo.get_by(DeckSession, user_id: user_id, deck_number: deck_number) do
      %DeckSession{} = session ->
        {:ok, session}

      nil ->
        attrs = %{user_id: user_id, deck_number: deck_number, track_id: track_id}

        %DeckSession{}
        |> DeckSession.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc """
  Updates a deck session's mutable fields (tempo, pitch, loops).

  ## Examples

      iex> update_deck_session(session, %{tempo_bpm: 128.0})
      {:ok, %DeckSession{}}

  """
  @spec update_deck_session(DeckSession.t(), map()) ::
          {:ok, DeckSession.t()} | {:error, Ecto.Changeset.t()}
  def update_deck_session(%DeckSession{} = session, attrs) do
    session
    |> DeckSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Loads (or changes) the track on a deck for the given user.
  Returns the updated session preloaded with track and stems.

  ## Examples

      iex> load_track_to_deck(user_id, 1, track_id)
      {:ok, %DeckSession{track: %Track{stems: [...]}}}

  """
  @spec load_track_to_deck(term(), integer(), binary()) ::
          {:ok, DeckSession.t()} | {:error, Ecto.Changeset.t()}
  def load_track_to_deck(user_id, deck_number, track_id) do
    with {:ok, session} <- get_or_create_deck_session(user_id, deck_number) do
      session
      |> DeckSession.changeset(%{track_id: track_id})
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          {:ok, Repo.preload(updated, [track: :stems], force: true)}

        error ->
          error
      end
    end
  end

  @doc """
  Returns the full deck state for a user's deck, preloaded with:
  - track (with stems)
  - the user's cue points for the loaded track

  Returns `nil` when no deck session exists.

  ## Examples

      iex> get_deck_state(user_id, 1)
      %{session: %DeckSession{track: %Track{stems: [...]}}, cue_points: [...]}

  """
  @spec get_deck_state(term(), integer()) :: map() | nil
  def get_deck_state(user_id, deck_number) do
    DeckSession
    |> where([ds], ds.user_id == ^user_id and ds.deck_number == ^deck_number)
    |> Repo.one()
    |> case do
      nil ->
        nil

      %DeckSession{} = session ->
        session = Repo.preload(session, [track: :stems])

        cue_points =
          if session.track_id do
            list_cue_points(session.track_id, user_id)
          else
            []
          end

        %{session: session, cue_points: cue_points}
    end
  end

  # ---------------------------------------------------------------------------
  # Stem Loop functions
  # ---------------------------------------------------------------------------

  @doc """
  Creates a stem loop.

  ## Examples

      iex> create_stem_loop(%{stem_id: sid, track_id: tid, user_id: uid, start_ms: 0, end_ms: 4000})
      {:ok, %StemLoop{}}

  """
  @spec create_stem_loop(map()) :: {:ok, StemLoop.t()} | {:error, Ecto.Changeset.t()}
  def create_stem_loop(attrs \\ %{}) do
    %StemLoop{}
    |> StemLoop.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all stem loops for a track belonging to a specific user,
  ordered by start_ms ascending. Preloads the stem association.
  """
  @spec list_stem_loops(binary(), term()) :: [StemLoop.t()]
  def list_stem_loops(track_id, user_id) do
    StemLoop
    |> where([sl], sl.track_id == ^track_id and sl.user_id == ^user_id)
    |> order_by([sl], asc: sl.start_ms)
    |> Repo.all()
    |> Repo.preload(:stem)
  end

  @doc """
  Gets a single stem loop by ID.

  Returns `nil` if the stem loop does not exist.
  """
  @spec get_stem_loop(binary()) :: StemLoop.t() | nil
  def get_stem_loop(id), do: Repo.get(StemLoop, id)

  @doc """
  Deletes a stem loop.

  ## Examples

      iex> delete_stem_loop(stem_loop)
      {:ok, %StemLoop{}}

  """
  @spec delete_stem_loop(StemLoop.t()) :: {:ok, StemLoop.t()} | {:error, Ecto.Changeset.t()}
  def delete_stem_loop(%StemLoop{} = stem_loop) do
    Repo.delete(stem_loop)
  end
end
