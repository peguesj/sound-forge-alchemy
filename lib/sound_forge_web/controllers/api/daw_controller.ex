defmodule SoundForgeWeb.API.DawController do
  @moduledoc """
  Controller for DAW stem export operations.
  Receives rendered WAV files from the client-side OfflineAudioContext,
  stores them on disk, and creates a new Stem record with source: "edited".
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Music
  alias SoundForge.Storage

  @doc """
  Receive an exported WAV file, store it, and create a new Stem record.

  Expects multipart params:
    - `file`      - the uploaded WAV file (%Plug.Upload{})
    - `track_id`  - UUID of the parent track
    - `stem_type` - the original stem type (e.g. "vocals", "drums")
  """
  def export(conn, %{
        "file" => %Plug.Upload{} = upload,
        "track_id" => track_id,
        "stem_type" => stem_type
      }) do
    with {:ok, _} <- Ecto.UUID.cast(track_id),
         {:ok, track} when not is_nil(track) <- Music.get_track(track_id),
         :ok <- authorize_track(conn, track),
         {:ok, base_stem_type} <- normalize_stem_type(stem_type) do
      do_export(conn, upload, track_id, base_stem_type)
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "Invalid track_id format"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{ok: false, error: "Access denied"})

      {:ok, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Track not found"})

      {:error, :invalid_track} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Track not found"})

      {:error, :invalid_stem_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "Invalid stem_type"})
    end
  end

  def export(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{ok: false, error: "Missing required fields: file, track_id, stem_type"})
  end

  defp do_export(conn, upload, track_id, stem_type) do
    # Build destination path under Storage.stems_path()/track_id/
    dest_dir = Path.join([Storage.stems_path(), track_id])
    File.mkdir_p!(dest_dir)

    filename = "#{stem_type}_edited_#{System.system_time(:second)}.wav"
    dest_path = Path.join(dest_dir, filename)

    # Copy uploaded temp file to permanent storage
    case File.cp(upload.path, dest_path) do
      :ok ->
        file_size =
          case File.stat(dest_path) do
            {:ok, %{size: s}} -> s
            _ -> nil
          end

        # Store a relative path for consistent URL generation
        relative_path = Path.join(["stems", track_id, filename])

        case Music.create_exported_stem(%{
               track_id: track_id,
               stem_type: stem_type,
               file_path: relative_path,
               file_size: file_size,
               source: "edited"
             }) do
          {:ok, stem} ->
            json(conn, %{ok: true, stem_id: stem.id, file_path: relative_path})

          {:error, changeset} ->
            # Clean up the file if DB insert fails
            File.rm(dest_path)

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{ok: false, error: inspect(changeset.errors)})
        end

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{ok: false, error: "Failed to store file: #{inspect(reason)}"})
    end
  end

  defp authorize_track(conn, track) do
    user_id = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:id)])

    if not is_nil(user_id) and track.user_id == user_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp normalize_stem_type(stem_type) when is_binary(stem_type) do
    stem_type =
      stem_type
      |> String.replace(~r/_edited$/, "")
      |> String.downcase()

    valid_stems =
      ~w(vocals drums bass other guitar piano electric_guitar acoustic_guitar synth strings wind)

    if stem_type in valid_stems do
      {:ok, String.to_atom(stem_type)}
    else
      {:error, :invalid_stem_type}
    end
  end

  defp normalize_stem_type(_stem_type), do: {:error, :invalid_stem_type}
end
