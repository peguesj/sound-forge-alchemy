defmodule SoundForgeWeb.API.TrackerControllerTest do
  use SoundForgeWeb.ConnCase

  describe "GET /api/tracker/health" do
    test "returns liveness JSON", %{conn: conn} do
      conn = get(conn, ~p"/api/tracker/health")
      assert json_response(conn, 200) == %{"online" => true}
    end
  end

  describe "GET /api/tracker/state" do
    test "returns current tracker state", %{conn: conn} do
      conn = get(conn, ~p"/api/tracker/state")
      body = json_response(conn, 200)
      assert body["online"] == true
      assert is_list(body["cards"])
      assert is_integer(body["card_count"])
    end
  end

  describe "POST /api/tracker/cards" do
    test "ingests a card and returns tracker status", %{conn: conn} do
      conn =
        post(conn, ~p"/api/tracker/cards", %{"run_id" => "r1", "evidence" => %{"pass" => true}})

      body = json_response(conn, 200)
      assert body["ok"] == true
      assert body["trackerStatus"]["online"] == true
      assert body["trackerStatus"]["cardCount"] >= 1
    end
  end

  describe "GET /api/tracker/events" do
    test "streams SSE with correct headers and initial snapshot", %{conn: conn} do
      conn = get(conn, ~p"/api/tracker/events?once=true")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/event-stream"
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "connection") == ["keep-alive"]
      assert conn.state == :chunked
      assert conn.resp_body =~ "data: "
      assert conn.resp_body =~ "\"online\":true"
    end
  end
end
