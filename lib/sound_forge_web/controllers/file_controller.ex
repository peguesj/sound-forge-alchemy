defmodule SoundForgeWeb.FileController do
  @moduledoc """
  Serves audio files from storage with path traversal protection.
  """
  use SoundForgeWeb, :controller

  alias SoundForge.Storage

  def serve(conn, %{"path" => path_parts}) do
    # Join path parts and sanitize
    file_path = Path.join(path_parts)

    # Decode any percent-encoded characters and check for traversal
    decoded = URI.decode(file_path)
    base = Storage.base_path()
    full_path = Path.join(base, decoded) |> Path.expand()

    # Ensure the resolved path stays within the storage directory
    if String.starts_with?(full_path, Path.expand(base) <> "/") do
      serve_file(conn, full_path)
    else
      conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
    end
  end

  defp serve_file(conn, path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        content_type = MIME.from_path(path)

        case get_req_header(conn, "range") do
          ["bytes=" <> range_spec] ->
            serve_range(conn, path, size, range_spec, content_type)

          _ ->
            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("accept-ranges", "bytes")
            |> put_resp_header("content-length", to_string(size))
            |> send_file(200, path)
        end

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "File not found"})
    end
  end

  defp serve_range(conn, path, total_size, range_spec, content_type) do
    case parse_range(range_spec, total_size) do
      {:ok, {start_byte, end_byte}} ->
        length = end_byte - start_byte + 1

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{total_size}")
        |> put_resp_header("content-length", to_string(length))
        |> send_file(206, path, start_byte, length)

      :error ->
        conn
        |> put_resp_header("content-range", "bytes */#{total_size}")
        |> send_resp(416, "Range Not Satisfiable")
    end
  end

  defp parse_range(range_spec, total_size) do
    case String.split(range_spec, "-", parts: 2) do
      [start_str, ""] -> parse_open_range(start_str, total_size)
      [start_str, end_str] -> parse_bounded_range(start_str, end_str, total_size)
      _ -> :error
    end
  end

  defp parse_open_range(start_str, total_size) do
    with {start_byte, _} when start_byte >= 0 <- Integer.parse(start_str),
         true <- start_byte < total_size do
      {:ok, {start_byte, total_size - 1}}
    else
      _ -> :error
    end
  end

  defp parse_bounded_range(start_str, end_str, total_size) do
    with {start_byte, _} when start_byte >= 0 <- Integer.parse(start_str),
         {end_byte_raw, _} when end_byte_raw >= 0 <- Integer.parse(end_str) do
      end_byte = min(end_byte_raw, total_size - 1)
      if start_byte <= end_byte, do: {:ok, {start_byte, end_byte}}, else: :error
    else
      _ -> :error
    end
  end
end
