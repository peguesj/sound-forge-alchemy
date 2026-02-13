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
  end
end
