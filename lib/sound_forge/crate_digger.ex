defmodule SoundForge.CrateDigger do
  @moduledoc """
  Context for CrateDigger — learning-focused Spotify playlist management.

  Provides CRUD for Crates (playlists with scoped stem config), per-track
  stem overrides, and helpers to resolve the effective stem config for playback.
  """

  import Ecto.Query, warn: false

  alias SoundForge.CrateDigger.Crate
  alias SoundForge.CrateDigger.CrateTrackConfig
  alias SoundForge.Repo
  alias SoundForge.Spotify

  # ---------------------------------------------------------------------------
  # Crate CRUD
  # ---------------------------------------------------------------------------

  @doc "List all crates for a user, ordered by most recently updated."
  @spec list_crates(integer()) :: [Crate.t()]
  def list_crates(user_id) do
    Crate
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
    |> Repo.preload(:track_configs)
  end

  @doc "Get a single crate by ID, preloading track configs."
  @spec get_crate(binary()) :: Crate.t() | nil
  def get_crate(id) do
    Crate
    |> Repo.get(id)
    |> Repo.preload(:track_configs)
  end

  @doc "Create a crate."
  @spec create_crate(map()) :: {:ok, Crate.t()} | {:error, Ecto.Changeset.t()}
  def create_crate(attrs) do
    %Crate{}
    |> Crate.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a crate."
  @spec update_crate(Crate.t(), map()) :: {:ok, Crate.t()} | {:error, Ecto.Changeset.t()}
  def update_crate(%Crate{} = crate, attrs) do
    crate
    |> Crate.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, :track_configs, force: true)}
      error -> error
    end
  end

  @doc "Delete a crate and all associated track configs (cascade)."
  @spec delete_crate(Crate.t()) :: {:ok, Crate.t()} | {:error, Ecto.Changeset.t()}
  def delete_crate(%Crate{} = crate) do
    Repo.delete(crate)
  end

  @doc "Rename a crate."
  @spec rename_crate(Crate.t(), String.t()) :: {:ok, Crate.t()} | {:error, Ecto.Changeset.t()}
  def rename_crate(%Crate{} = crate, name) when is_binary(name) and name != "" do
    update_crate(crate, %{name: String.trim(name)})
  end

  @doc """
  Refresh a crate by re-fetching its playlist from Spotify.

  Preserves existing `stem_config` and per-track `track_configs`.
  Only `playlist_data` (track list) is updated.
  """
  @spec refresh_crate(Crate.t()) :: {:ok, Crate.t()} | {:error, term()}
  def refresh_crate(%Crate{spotify_playlist_id: playlist_id} = crate) do
    spotify_url = "https://open.spotify.com/playlist/#{playlist_id}"

    with {:ok, playlist} <- Spotify.fetch_metadata(spotify_url),
         {:ok, tracks} <- extract_tracks(playlist) do
      update_crate(crate, %{playlist_data: tracks})
    end
  end

  # ---------------------------------------------------------------------------
  # Playlist loading
  # ---------------------------------------------------------------------------

  @doc """
  Load a Spotify playlist URL into a Crate for the given user.

  Fetches playlist metadata from Spotify, normalises track data into the
  `playlist_data` JSONB field, and upserts the Crate record.

  Returns `{:ok, crate}` or `{:error, reason}`.
  """
  @spec load_spotify_playlist(integer(), String.t()) ::
          {:ok, Crate.t()} | {:error, term()}
  def load_spotify_playlist(user_id, spotify_url) do
    with {:ok, playlist} <- Spotify.fetch_metadata(spotify_url),
         {:ok, tracks} <- extract_tracks(playlist),
         playlist_id = playlist["id"],
         name = playlist["name"] || "Untitled Playlist",
         crate = find_or_build_crate(user_id, playlist_id, name),
         attrs = %{
           name: name,
           spotify_playlist_id: playlist_id,
           playlist_data: tracks,
           user_id: user_id
         },
         {:ok, saved} <- upsert_crate(crate, attrs) do
      {:ok, saved}
    end
  end

  # ---------------------------------------------------------------------------
  # Stem config
  # ---------------------------------------------------------------------------

  @doc """
  Update the playlist-level stem config on a Crate.

  `enabled_stems` is a list of stem name strings: ["vocals", "drums", "bass", "other"].
  """
  @spec update_crate_stem_config(Crate.t(), [String.t()]) ::
          {:ok, Crate.t()} | {:error, Ecto.Changeset.t()}
  def update_crate_stem_config(%Crate{} = crate, enabled_stems) when is_list(enabled_stems) do
    update_crate(crate, %{stem_config: %{"enabled_stems" => enabled_stems}})
  end

  @doc """
  Upsert a per-track stem override for a specific track in a crate.

  Pass `stem_override: nil` to clear the override (reset to playlist default).
  """
  @spec set_track_stem_override(binary(), String.t(), [String.t()] | nil) ::
          {:ok, CrateTrackConfig.t()} | {:error, Ecto.Changeset.t()}
  def set_track_stem_override(crate_id, spotify_track_id, nil) do
    case find_track_config(crate_id, spotify_track_id) do
      nil -> {:ok, nil}
      config -> Repo.delete(config)
    end
  end

  def set_track_stem_override(crate_id, spotify_track_id, enabled_stems)
      when is_list(enabled_stems) do
    attrs = %{
      crate_id: crate_id,
      spotify_track_id: spotify_track_id,
      stem_override: %{"enabled_stems" => enabled_stems}
    }

    case find_track_config(crate_id, spotify_track_id) do
      nil ->
        %CrateTrackConfig{}
        |> CrateTrackConfig.changeset(attrs)
        |> Repo.insert()

      config ->
        config
        |> CrateTrackConfig.changeset(%{stem_override: %{"enabled_stems" => enabled_stems}})
        |> Repo.update()
    end
  end

  @doc """
  Resolve the effective stem config for a track.

  Returns the per-track override if one exists, otherwise falls back to the
  crate-level default. Always returns a list of stem name strings.
  """
  @spec get_effective_stem_config(Crate.t(), String.t()) :: [String.t()]
  def get_effective_stem_config(%Crate{} = crate, spotify_track_id) do
    case find_track_config(crate.id, spotify_track_id) do
      %CrateTrackConfig{stem_override: %{"enabled_stems" => stems}} when is_list(stems) ->
        stems

      _ ->
        crate.stem_config["enabled_stems"] || ["vocals", "drums", "bass", "other"]
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp find_track_config(crate_id, spotify_track_id) do
    CrateTrackConfig
    |> where([c], c.crate_id == ^crate_id and c.spotify_track_id == ^spotify_track_id)
    |> Repo.one()
  end

  defp find_or_build_crate(user_id, playlist_id, name) do
    case Repo.get_by(Crate, user_id: user_id, spotify_playlist_id: playlist_id) do
      nil -> %Crate{name: name, spotify_playlist_id: playlist_id, user_id: user_id}
      crate -> crate
    end
  end

  defp upsert_crate(%Crate{id: nil} = crate, attrs) do
    crate
    |> Crate.changeset(attrs)
    |> Repo.insert()
  end

  defp upsert_crate(%Crate{} = crate, attrs) do
    crate
    |> Crate.changeset(attrs)
    |> Repo.update()
  end

  defp extract_tracks(%{"tracks" => %{"items" => items}}) when is_list(items) do
    tracks =
      items
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn item ->
        track = item["track"] || item
        artists = track["artists"] || []

        %{
          "spotify_id" => track["id"],
          "title" => track["name"],
          "artist" => artists |> Enum.map(& &1["name"]) |> Enum.join(", "),
          "artists" => Enum.map(artists, & &1["name"]),
          "album" => get_in(track, ["album", "name"]),
          "artwork_url" => get_in(track, ["album", "images", Access.at(0), "url"]),
          "duration_ms" => track["duration_ms"],
          "release_date" => get_in(track, ["album", "release_date"]),
          "explicit" => track["explicit"] || false,
          "popularity" => track["popularity"]
        }
      end)

    {:ok, tracks}
  end

  defp extract_tracks(_), do: {:ok, []}
end
