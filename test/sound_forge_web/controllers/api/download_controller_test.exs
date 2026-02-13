defmodule SoundForgeWeb.API.DownloadControllerTest do
  use SoundForgeWeb.ConnCase

  alias SoundForge.Music

  setup :register_and_auth_api_user

  describe "POST /api/download/track" do
    test "creates download job for valid URL", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/download/track", %{url: "https://open.spotify.com/track/12345"})

      assert %{
               "success" => true,
               "job_id" => job_id,
               "status" => status
             } = json_response(conn, 201)

      assert is_binary(job_id)
      assert status in ["queued", "pending", "downloading", "processing", "completed"]
    end

    test "returns error when url parameter is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/download/track", %{})

      assert %{"error" => "url parameter is required"} = json_response(conn, 400)
    end

    test "returns error when url is empty string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/download/track", %{url: ""})

      assert %{"error" => "url parameter is required"} = json_response(conn, 400)
    end
  end

  describe "GET /api/download/job/:id" do
    test "returns job status for valid job ID", %{conn: conn} do
      # Create a real job first
      {:ok, track} = Music.create_track(%{title: "Test Track"})
      {:ok, job} = Music.create_download_job(%{track_id: track.id, status: :queued})

      conn = get(conn, "/api/download/job/#{job.id}")

      assert %{
               "success" => true,
               "job_id" => _job_id,
               "status" => status,
               "progress" => progress
             } = json_response(conn, 200)

      assert status in ["queued", "downloading", "processing", "completed", "failed"]
      assert is_number(progress)
    end

    test "returns 404 for non-existent job ID", %{conn: conn} do
      conn = get(conn, "/api/download/job/#{Ecto.UUID.generate()}")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end

    test "returns 404 for invalid job ID format", %{conn: conn} do
      conn = get(conn, "/api/download/job/not-a-uuid")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end
  end
end
