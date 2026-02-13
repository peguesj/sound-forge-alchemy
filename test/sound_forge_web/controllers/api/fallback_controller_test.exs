defmodule SoundForgeWeb.API.FallbackControllerTest do
  use SoundForgeWeb.ConnCase

  alias SoundForgeWeb.API.FallbackController

  describe "call/2" do
    test "returns 404 for :not_found error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert json_response(conn, 404)["error"] == "Not found"
    end

    test "returns 422 for changeset error", %{conn: conn} do
      changeset =
        %SoundForge.Music.Track{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:title, "can't be blank")

      conn = FallbackController.call(conn, {:error, changeset})
      body = json_response(conn, 422)
      assert body["error"] == "Validation failed"
      assert is_map(body["details"])
      assert body["details"]["title"] == ["can't be blank"]
    end

    test "returns 400 for string error reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "Something went wrong"})
      assert json_response(conn, 400)["error"] == "Something went wrong"
    end

    test "returns 400 for atom error reason", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_input})
      assert json_response(conn, 400)["error"] == "invalid_input"
    end

    test "handles changeset with multiple errors on multiple fields", %{conn: conn} do
      changeset =
        %SoundForge.Music.Track{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:title, "can't be blank")
        |> Ecto.Changeset.add_error(:title, "is too short")
        |> Ecto.Changeset.add_error(:artist, "is invalid")

      conn = FallbackController.call(conn, {:error, changeset})
      body = json_response(conn, 422)
      assert length(body["details"]["title"]) == 2
      assert length(body["details"]["artist"]) == 1
    end
  end
end
