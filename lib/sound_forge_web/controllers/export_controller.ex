defmodule SoundForgeWeb.ExportController do
  @moduledoc """
  Controller for exporting stems and analysis data.
  Enforces owner-scoped access control.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music
  alias SoundForge.Storage

  def download_stem(conn, %{"id" => stem_id}) do
    with {:ok, _} <- Ecto.UUID.cast(stem_id),
         {:ok, stem} <- fetch_stem(stem_id),
         {:ok, track} <- fetch_track(stem.track_id),
         :ok <- authorize(conn, track) do
      serve_download(conn, stem.file_path, stem_filename(stem))
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "Stem not found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "Access denied"})
      :error -> conn |> put_status(:not_found) |> json(%{error: "Stem not found"})
    end
  end

  def download_all_stems(conn, %{"track_id" => track_id}) do
    with {:ok, _} <- Ecto.UUID.cast(track_id),
         {:ok, track} <- fetch_track_with_details(track_id),
         :ok <- authorize(conn, track),
         {:ok, stems} <- check_stems(track.stems) do
      zip_path = create_stems_zip(track, stems)
      zip_filename = "#{sanitize_filename(track.title)}_stems.zip"

      try do
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{zip_filename}"))
        |> send_file(200, zip_path)
      after
        File.rm(zip_path)
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Track not found"})

      {:error, :no_stems} ->
        conn |> put_status(:not_found) |> json(%{error: "No stems available"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "Access denied"})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Track not found"})
    end
  end

  def export_analysis(conn, %{"track_id" => track_id}) do
    with {:ok, _} <- Ecto.UUID.cast(track_id),
         {:ok, track} <- fetch_track(track_id),
         :ok <- authorize(conn, track),
         {:ok, result} <- fetch_analysis(track_id) do
      export = %{
        track: %{
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration_ms: track.duration
        },
        analysis: %{
          tempo: result.tempo,
          key: result.key,
          energy: result.energy,
          spectral_centroid: result.spectral_centroid,
          spectral_rolloff: result.spectral_rolloff,
          zero_crossing_rate: result.zero_crossing_rate,
          features: result.features
        },
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      filename = "#{sanitize_filename(track.title)}_analysis.json"

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> json(export)
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})

      {:error, :no_analysis} ->
        conn |> put_status(:not_found) |> json(%{error: "No analysis data"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "Access denied"})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})
    end
  end

  # Fetchers

  defp fetch_stem(id) do
    {:ok, Music.get_stem!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_track(id) do
    {:ok, Music.get_track!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_track_with_details(id) do
    {:ok, Music.get_track_with_details!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_analysis(track_id) do
    case Music.get_analysis_result_for_track(track_id) do
      nil -> {:error, :no_analysis}
      result -> {:ok, result}
    end
  end

  defp check_stems([_ | _] = stems), do: {:ok, stems}
  defp check_stems(_), do: {:error, :no_stems}

  # Authorization: track owner or nil user_id (legacy/public tracks)

  defp authorize(conn, track) do
    user_id = get_user_id(conn)

    if is_nil(track.user_id) or track.user_id == user_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp get_user_id(conn) do
    case conn.assigns do
      %{current_user: %{id: id}} -> id
      %{current_scope: %{user: %{id: id}}} -> id
      _ -> nil
    end
  end

  # File serving

  defp serve_download(conn, file_path, filename) do
    full_path = resolve_path(file_path)

    if full_path && File.exists?(full_path) do
      content_type = MIME.from_path(full_path)

      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_file(200, full_path)
    else
      conn |> put_status(:not_found) |> json(%{error: "File not found"})
    end
  end

  defp resolve_path(nil), do: nil

  defp resolve_path(path) do
    if String.starts_with?(path, "/") do
      # Absolute paths from workers are trusted, but reject traversal
      expanded = Path.expand(path)
      if String.contains?(path, ".."), do: nil, else: expanded
    else
      # Relative paths must stay within storage directory
      full = Path.join(Storage.base_path(), path) |> Path.expand()
      base = Path.expand(Storage.base_path())
      if String.starts_with?(full, base <> "/") or full == base, do: full, else: nil
    end
  end

  defp create_stems_zip(track, stems) do
    tmp_dir = System.tmp_dir!()
    zip_path = Path.join(tmp_dir, "sfa_stems_#{track.id}.zip")

    files =
      stems
      |> Enum.filter(fn stem -> stem.file_path && File.exists?(resolve_path(stem.file_path)) end)
      |> Enum.flat_map(fn stem ->
        full_path = resolve_path(stem.file_path)
        ext = Path.extname(full_path)
        entry_name = "#{sanitize_filename(track.title)} - #{stem.stem_type}#{ext}"

        case File.read(full_path) do
          {:ok, data} -> [{String.to_charlist(entry_name), data}]
          {:error, _} -> []
        end
      end)

    {:ok, _} = :zip.create(String.to_charlist(zip_path), files)
    zip_path
  end

  defp stem_filename(stem) do
    ext = if stem.file_path, do: Path.extname(stem.file_path), else: ".mp3"
    "#{stem.stem_type}#{ext}"
  end

  defp sanitize_filename(name) when is_binary(name) do
    name
    |> String.replace(~r/[^\w\s\-.]/, "")
    |> String.trim()
    |> String.slice(0, 100)
  end

  defp sanitize_filename(_), do: "track"
end
