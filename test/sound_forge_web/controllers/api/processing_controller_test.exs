defmodule SoundForgeWeb.API.ProcessingControllerTest do
  use SoundForgeWeb.ConnCase

  alias SoundForge.Music

  describe "POST /api/processing/separate" do
    test "creates separation job with default model", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/processing/separate", %{file_path: "/tmp/test.mp3"})

      assert %{
               "success" => true,
               "job_id" => job_id,
               "status" => status,
               "model" => model
             } = json_response(conn, 201)

      assert is_binary(job_id)
      assert status in ["queued", "pending", "processing", "completed"]
      assert model == "htdemucs"
    end

    test "creates separation job with specified model", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/processing/separate", %{
          file_path: "/tmp/test.mp3",
          model: "htdemucs_ft"
        })

      assert %{
               "success" => true,
               "model" => "htdemucs_ft"
             } = json_response(conn, 201)
    end

    test "returns error when file_path parameter is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/processing/separate", %{})

      assert %{"error" => "file_path parameter is required"} = json_response(conn, 400)
    end

    test "returns error when file_path is empty string", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/processing/separate", %{file_path: ""})

      assert %{"error" => "file_path parameter is required"} = json_response(conn, 400)
    end
  end

  describe "GET /api/processing/job/:id" do
    test "returns job status for valid job ID", %{conn: conn} do
      {:ok, track} = Music.create_track(%{title: "Test Track"})

      {:ok, job} =
        Music.create_processing_job(%{
          track_id: track.id,
          model: "htdemucs",
          status: :queued,
          options: %{file_path: "/tmp/test.mp3", model: "htdemucs"}
        })

      conn = get(conn, "/api/processing/job/#{job.id}")

      assert %{
               "success" => true,
               "job_id" => _job_id,
               "status" => status,
               "progress" => progress,
               "model" => model
             } = json_response(conn, 200)

      assert status in ["queued", "downloading", "processing", "completed", "failed"]
      assert is_number(progress)
      assert is_binary(model)
    end

    test "returns 404 for non-existent job ID", %{conn: conn} do
      conn = get(conn, "/api/processing/job/#{Ecto.UUID.generate()}")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end

    test "returns 404 for invalid job ID format", %{conn: conn} do
      conn = get(conn, "/api/processing/job/not-a-uuid")
      assert %{"error" => "Job not found"} = json_response(conn, 404)
    end
  end

  describe "GET /api/processing/models" do
    test "returns list of available models", %{conn: conn} do
      conn = get(conn, "/api/processing/models")

      assert %{
               "success" => true,
               "models" => models
             } = json_response(conn, 200)

      assert is_list(models)
      assert length(models) > 0

      [first_model | _] = models
      assert Map.has_key?(first_model, "name")
      assert Map.has_key?(first_model, "description")
      assert Map.has_key?(first_model, "stems")
    end

    test "models include htdemucs", %{conn: conn} do
      conn = get(conn, "/api/processing/models")

      assert %{"models" => models} = json_response(conn, 200)
      assert Enum.any?(models, fn model -> model["name"] == "htdemucs" end)
    end
  end
end
