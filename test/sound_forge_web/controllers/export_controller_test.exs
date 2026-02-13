defmodule SoundForgeWeb.ExportControllerTest do
  use SoundForgeWeb.ConnCase

  import SoundForge.MusicFixtures

  setup :register_and_log_in_user

  describe "GET /export/stem/:id" do
    test "downloads a stem file when authorized", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      processing_job = processing_job_fixture(%{track_id: track.id})

      # Create a temp file to serve
      tmp_path =
        Path.join(System.tmp_dir!(), "test_stem_#{System.unique_integer([:positive])}.wav")

      File.write!(tmp_path, "fake audio data")

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :vocals,
          file_path: tmp_path
        })

      conn = get(conn, ~p"/export/stem/#{stem.id}")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "vocals"

      File.rm(tmp_path)
    end

    test "returns 404 for nonexistent stem", %{conn: conn} do
      conn = get(conn, ~p"/export/stem/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 404 for invalid UUID", %{conn: conn} do
      conn = get(conn, ~p"/export/stem/not-a-uuid")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 403 when accessing another user's stem", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{user_id: other_user.id})
      processing_job = processing_job_fixture(%{track_id: track.id})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :vocals
        })

      conn = get(conn, ~p"/export/stem/#{stem.id}")
      assert json_response(conn, 403)["error"] =~ "Access denied"
    end

    test "allows access to tracks with nil user_id (legacy)", %{conn: conn} do
      track = track_fixture(%{user_id: nil})
      processing_job = processing_job_fixture(%{track_id: track.id})

      tmp_path =
        Path.join(System.tmp_dir!(), "test_stem_legacy_#{System.unique_integer([:positive])}.wav")

      File.write!(tmp_path, "fake audio data")

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :drums,
          file_path: tmp_path
        })

      conn = get(conn, ~p"/export/stem/#{stem.id}")
      assert response(conn, 200)

      File.rm(tmp_path)
    end
  end

  describe "GET /export/stems/:track_id" do
    test "downloads zip file with stems when authorized", %{conn: conn, user: user} do
      track = track_fixture(%{title: "My Song", user_id: user.id})
      processing_job = processing_job_fixture(%{track_id: track.id})

      # Create temp stem files
      tmp1 = Path.join(System.tmp_dir!(), "test_vocals_#{System.unique_integer([:positive])}.wav")
      tmp2 = Path.join(System.tmp_dir!(), "test_drums_#{System.unique_integer([:positive])}.wav")
      File.write!(tmp1, "vocals audio data")
      File.write!(tmp2, "drums audio data")

      stem_fixture(%{
        track_id: track.id,
        processing_job_id: processing_job.id,
        stem_type: :vocals,
        file_path: tmp1
      })

      stem_fixture(%{
        track_id: track.id,
        processing_job_id: processing_job.id,
        stem_type: :drums,
        file_path: tmp2
      })

      conn = get(conn, ~p"/export/stems/#{track.id}")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> List.first() =~ "zip"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "My Song"
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ ".zip"

      # Verify zip content
      {:ok, zip_entries} = :zip.list_dir(conn.resp_body)
      # :zip.list_dir returns [:zip_comment | entries], first is comment
      entry_names =
        zip_entries |> tl() |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

      assert Enum.any?(entry_names, &String.contains?(&1, "vocals"))
      assert Enum.any?(entry_names, &String.contains?(&1, "drums"))

      File.rm(tmp1)
      File.rm(tmp2)
    end

    test "returns 404 when track has no stems", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      conn = get(conn, ~p"/export/stems/#{track.id}")
      assert json_response(conn, 404)["error"] =~ "No stems"
    end

    test "returns 404 for nonexistent track", %{conn: conn} do
      conn = get(conn, ~p"/export/stems/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 403 when accessing another user's track stems", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{user_id: other_user.id})
      conn = get(conn, ~p"/export/stems/#{track.id}")
      assert json_response(conn, 403)["error"] =~ "Access denied"
    end

    test "returns 404 for invalid UUID", %{conn: conn} do
      conn = get(conn, ~p"/export/stems/not-a-uuid")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "GET /export/analysis/:track_id" do
    test "exports analysis as JSON when authorized", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      analysis_job = SoundForge.MusicFixtures.analysis_job_fixture(%{track_id: track.id})

      SoundForge.MusicFixtures.analysis_result_fixture(%{
        track_id: track.id,
        analysis_job_id: analysis_job.id,
        tempo: 128.0,
        key: "A minor",
        energy: 0.85
      })

      conn = get(conn, ~p"/export/analysis/#{track.id}")
      assert response = json_response(conn, 200)
      assert response["track"]["title"] == track.title
      assert response["analysis"]["tempo"] == 128.0
      assert response["analysis"]["key"] == "A minor"
      assert response["analysis"]["energy"] == 0.85
      assert response["exported_at"]
      assert get_resp_header(conn, "content-disposition") |> List.first() =~ "analysis.json"
    end

    test "returns 404 when no analysis exists", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      conn = get(conn, ~p"/export/analysis/#{track.id}")
      assert json_response(conn, 404)["error"] =~ "No analysis"
    end

    test "returns 403 when accessing another user's analysis", %{conn: conn} do
      other_user = SoundForge.AccountsFixtures.user_fixture()
      track = track_fixture(%{user_id: other_user.id})
      conn = get(conn, ~p"/export/analysis/#{track.id}")
      assert json_response(conn, 403)["error"] =~ "Access denied"
    end

    test "returns 404 for nonexistent track", %{conn: conn} do
      conn = get(conn, ~p"/export/analysis/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] =~ "Not found"
    end

    test "returns 404 for invalid UUID", %{conn: conn} do
      conn = get(conn, ~p"/export/analysis/not-a-uuid")
      assert json_response(conn, 404)["error"] =~ "Not found"
    end
  end

  describe "path traversal protection" do
    test "stem with path traversal in file_path returns 404", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      processing_job = processing_job_fixture(%{track_id: track.id})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :vocals,
          file_path: "/etc/../etc/passwd"
        })

      conn = get(conn, ~p"/export/stem/#{stem.id}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "stem with nil file_path returns 404", %{conn: conn, user: user} do
      track = track_fixture(%{user_id: user.id})
      processing_job = processing_job_fixture(%{track_id: track.id})

      stem =
        stem_fixture(%{
          track_id: track.id,
          processing_job_id: processing_job.id,
          stem_type: :vocals,
          file_path: nil
        })

      conn = get(conn, ~p"/export/stem/#{stem.id}")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end
end
