defmodule SoundForgeWeb.FileControllerTest do
  use SoundForgeWeb.ConnCase

  setup :register_and_log_in_user

  setup do
    # Create a test file in storage
    base = SoundForge.Storage.base_path()
    File.mkdir_p!(base)
    test_file = Path.join(base, "test_audio.mp3")
    File.write!(test_file, "ID3" <> :crypto.strong_rand_bytes(2048))

    on_exit(fn -> File.rm(test_file) end)

    %{test_file: test_file}
  end

  describe "serve/2" do
    test "serves an existing file", %{conn: conn} do
      conn = get(conn, ~p"/files/test_audio.mp3")
      assert conn.status == 200
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "audio/mpeg"
    end

    test "returns 404 for nonexistent file", %{conn: conn} do
      conn = get(conn, ~p"/files/nonexistent.wav")
      assert json_response(conn, 404)["error"] == "File not found"
    end

    test "blocks directory traversal", %{conn: conn} do
      conn = get(conn, "/files/../../../etc/passwd")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "blocks encoded directory traversal", %{conn: conn} do
      conn = get(conn, "/files/foo/..%2F..%2Fetc/passwd")
      # After URL decoding, if ".." is present it should be blocked
      assert conn.status in [403, 404]
    end

    test "serves file with range request", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=0-100")
        |> get(~p"/files/test_audio.mp3")

      assert conn.status == 206
      assert [range_header] = get_resp_header(conn, "content-range")
      assert range_header =~ ~r/bytes 0-100\/\d+/
    end

    test "returns 416 for invalid range", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=999999-")
        |> get(~p"/files/test_audio.mp3")

      assert conn.status == 416
    end

    test "returns 416 for malformed range header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=abc-def")
        |> get(~p"/files/test_audio.mp3")

      assert conn.status == 416
    end

    test "returns 416 for negative range values", %{conn: conn} do
      conn =
        conn
        |> put_req_header("range", "bytes=-1-100")
        |> get(~p"/files/test_audio.mp3")

      assert conn.status == 416
    end

    test "blocks null byte injection in path", %{conn: conn} do
      conn = get(conn, "/files/test%00.mp3")
      assert conn.status in [400, 403, 404]
    end

    test "blocks path with prefix overlap", %{conn: conn} do
      # If storage base is "priv/uploads", a path like "../uploads_backup/evil.txt"
      # should not be served even though it starts with similar prefix
      conn = get(conn, "/files/../uploads_backup/evil.txt")
      assert conn.status in [403, 404]
    end

    test "serves file in subdirectory", %{conn: conn} do
      base = SoundForge.Storage.base_path()
      sub_dir = Path.join(base, "subdir")
      File.mkdir_p!(sub_dir)
      File.write!(Path.join(sub_dir, "nested.mp3"), "ID3" <> :crypto.strong_rand_bytes(100))

      conn = get(conn, ~p"/files/subdir/nested.mp3")
      assert conn.status == 200

      File.rm_rf!(sub_dir)
    end
  end
end
