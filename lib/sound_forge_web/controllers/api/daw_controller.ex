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
  def export(conn, %{"file" => %Plug.Upload{} = upload, "track_id" => track_id, "stem_type" => stem_type}) do
    # Validate track_id is a proper UUID
    case Ecto.UUID.cast(track_id) do
      {:ok, _} -> do_export(conn, upload, track_id, stem_type)
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{ok: false, error: "Invalid track_id format"})
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

        # Normalize stem_type to a valid atom (strip any _edited suffix that might
        # have been sent and use the base type)
        base_stem_type =
          stem_type
          |> String.replace(~r/_edited$/, "")
          |> String.to_existing_atom()

        # Store a relative path for consistent URL generation
        relative_path = Path.join(["stems", track_id, filename])

        case Music.create_exported_stem(%{
               track_id: track_id,
               stem_type: base_stem_type,
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
end
