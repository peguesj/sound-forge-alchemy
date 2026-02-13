defmodule SoundForgeWeb.FileController do
  use SoundForgeWeb, :controller

  alias SoundForge.Storage

  def serve(conn, %{"path" => path_parts}) do
    # Join path parts and sanitize
    file_path = Path.join(path_parts)

    # Prevent directory traversal
    if String.contains?(file_path, "..") do
      conn |> put_status(:forbidden) |> json(%{error: "Forbidden"})
    else
      full_path = Path.join(Storage.base_path(), file_path)
      serve_file(conn, full_path)
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

      {:error, :enoent} ->
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
      [start_str, ""] ->
        start_byte = String.to_integer(start_str)
        if start_byte < total_size, do: {:ok, {start_byte, total_size - 1}}, else: :error

      [start_str, end_str] ->
        start_byte = String.to_integer(start_str)
        end_byte = min(String.to_integer(end_str), total_size - 1)
        if start_byte <= end_byte, do: {:ok, {start_byte, end_byte}}, else: :error

      _ ->
        :error
    end
  end
end
