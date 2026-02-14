defmodule Mix.Tasks.BackfillAlbums do
  @moduledoc """
  Backfill album metadata for tracks that have a spotify_id but no album.

  Uses SpotDL.fetch_metadata/1 to get album names from Spotify.

  ## Usage

      mix backfill_albums
  """
  use Mix.Task

  @shortdoc "Backfill album metadata from Spotify for tracks missing album data"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    import Ecto.Query

    tracks =
      SoundForge.Music.Track
      |> where([t], not is_nil(t.spotify_id) and t.spotify_id != "")
      |> where([t], is_nil(t.album))
      |> select([t], %{id: t.id, spotify_id: t.spotify_id})
      |> SoundForge.Repo.all()

    if tracks == [] do
      Mix.shell().info("No tracks need album backfill.")
    else
      Mix.shell().info("Found #{length(tracks)} tracks to backfill...")
      backfill(tracks)
    end
  end

  defp backfill(tracks) do
    {updated, failed} =
      tracks
      |> Enum.reduce({0, 0}, fn track, {ok, err} ->
        url = "https://open.spotify.com/track/#{track.spotify_id}"

        case SoundForge.Audio.SpotDL.fetch_metadata(url) do
          {:ok, [%{"album_name" => album} | _]} when album != "" and not is_nil(album) ->
            SoundForge.Repo.get(SoundForge.Music.Track, track.id)
            |> Ecto.Changeset.change(%{album: album})
            |> SoundForge.Repo.update!()

            {ok + 1, err}

          _ ->
            {ok, err + 1}
        end
      end)

    Mix.shell().info("Backfill complete: #{updated} updated, #{failed} failed")
  end
end
