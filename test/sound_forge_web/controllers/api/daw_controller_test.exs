defmodule SoundForgeWeb.API.DawControllerTest do
  use SoundForgeWeb.ConnCase

  import SoundForge.AccountsFixtures

  setup do
    user = user_fixture()
    conn = build_conn() |> log_in_user(user)
    %{conn: conn, user: user}
  end

  describe "POST /api/daw/export" do
    test "returns 400 when missing required fields", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/daw/export", %{})

      assert json_response(conn, 400)["error"] =~ "Missing required fields"
    end

    test "returns 400 for invalid track_id format", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp_wav(),
        filename: "test.wav",
        content_type: "audio/wav"
      }

      conn =
        conn
        |> post("/api/daw/export", %{
          "file" => upload,
          "track_id" => "not-a-uuid",
          "stem_type" => "vocals"
        })

      assert json_response(conn, 400)["error"] =~ "Invalid track_id"
    end

    test "returns 400 when file param is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/daw/export", %{
          "track_id" => Ecto.UUID.generate(),
          "stem_type" => "vocals"
        })

      assert json_response(conn, 400)["error"] =~ "Missing required fields"
    end
  end

  describe "POST /api/daw/export with valid data" do
    test "exports stem file successfully", %{conn: conn, user: user} do
      import SoundForge.MusicFixtures

      track = track_fixture(%{title: "DAW Export Track", user_id: user.id})

      upload = %Plug.Upload{
        path: write_temp_wav(),
        filename: "vocals_edited.wav",
        content_type: "audio/wav"
      }

      conn =
        conn
        |> post("/api/daw/export", %{
          "file" => upload,
          "track_id" => track.id,
          "stem_type" => "vocals"
        })

      resp = json_response(conn, 200)
      assert resp["ok"] == true
      assert is_binary(resp["stem_id"])
      assert is_binary(resp["file_path"])
    end
  end

  describe "POST /api/daw/export authentication" do
    test "redirects unauthenticated users" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("content-type", "application/json")
        |> post("/api/daw/export", %{})

      # browser_api pipeline requires session auth; unauthenticated gets redirected
      assert redirected_to(conn) == "/users/log-in"
    end
  end

  defp write_temp_wav do
    path =
      Path.join(System.tmp_dir!(), "test_daw_export_#{System.unique_integer([:positive])}.wav")

    File.write!(path, <<0::size(1024)>>)
    path
  end
end
