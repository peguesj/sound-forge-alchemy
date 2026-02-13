defmodule SoundForgeWeb.API.AnalysisControllerTest do
  use SoundForgeWeb.ConnCase

  alias SoundForge.Music

  setup context do
    context = register_and_auth_api_user(context)

    tmp_dir = System.tmp_dir!()
    tmp_file = Path.join(tmp_dir, "sfa_test_#{System.unique_integer([:positive])}.mp3")
    File.write!(tmp_file, "fake audio content")
    on_exit(fn -> File.rm(tmp_file) end)

    Map.put(context, :tmp_file, tmp_file)
  end

  describe "POST /api/analysis/analyze" do
    test "creates analysis job with default type", %{conn: conn, tmp_file: tmp_file} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{file_path: tmp_file})

      assert %{
               "success" => true,
               "job_id" => job_id,
               "status" => status,
               "type" => type
             } = json_response(conn, 201)

      assert is_binary(job_id)
      assert status in ["queued", "pending", "processing", "completed"]
      assert type == "full"
    end

    test "creates analysis job with specified type", %{conn: conn, tmp_file: tmp_file} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{
          file_path: tmp_file,
          type: "tempo"
        })

      assert %{
               "success" => true,
               "type" => "tempo"
             } = json_response(conn, 201)
    end

    test "returns error when file does not exist", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{file_path: "/tmp/nonexistent_audio.mp3"})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Audio file not found"
    end

    test "returns error when file_path parameter is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{})

      assert %{"error" => "file_path parameter is required"} = json_response(conn, 400)
    end

    test "returns error when file_path is empty string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{file_path: ""})

      assert %{"error" => "file_path parameter is required"} = json_response(conn, 400)
    end

    test "returns error for invalid analysis type", %{conn: conn, tmp_file: tmp_file} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/analysis/analyze", %{
          file_path: tmp_file,
          type: "invalid_type"
        })

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid analysis type"
    end
  end

  describe "GET /api/analysis/job/:id" do
    test "returns job status for valid job ID", %{conn: conn} do
      {:ok, track} = Music.create_track(%{title: "Test Track"})

      {:ok, job} =
        Music.create_analysis_job(%{
          track_id: track.id,
          status: :queued,
          results: %{type: "full", file_path: "/tmp/test.mp3"}
        })

      conn = get(conn, "/api/analysis/job/#{job.id}")

      assert %{
               "success" => true,
               "job_id" => _job_id,
               "status" => status,
               "progress" => progress,
               "type" => type
             } = json_response(conn, 200)

      assert status in ["queued", "downloading", "processing", "completed", "failed"]
      assert is_number(progress)
      assert is_binary(type)
    end

    test "returns 404 for non-existent job ID", %{conn: conn} do
      conn = get(conn, "/api/analysis/job/#{Ecto.UUID.generate()}")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end

    test "returns 404 for invalid job ID format", %{conn: conn} do
      conn = get(conn, "/api/analysis/job/not-a-uuid")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end
  end
end
