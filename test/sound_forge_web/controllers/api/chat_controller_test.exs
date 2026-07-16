defmodule SoundForgeWeb.API.ChatControllerTest do
  use SoundForgeWeb.ConnCase

  describe "GET /api/chat/presence" do
    test "returns presence JSON", %{conn: conn} do
      conn = get(conn, ~p"/api/chat/presence")
      assert %{"participants" => participants} = json_response(conn, 200)
      assert is_list(participants)
    end
  end

  describe "POST /api/chat/messages" do
    test "posts a message", %{conn: conn} do
      conn =
        post(conn, ~p"/api/chat/messages", %{
          "sender" => "test-suite",
          "body" => "hello",
          "meta" => %{"source" => "test"}
        })

      body = json_response(conn, 200)
      assert body["ok"] == true
      assert body["message"]["sender"] == "test-suite"
      assert body["message"]["body"] == "hello"
    end

    test "rejects message without sender/body", %{conn: conn} do
      conn = post(conn, ~p"/api/chat/messages", %{"body" => "hello"})
      assert %{"ok" => false} = json_response(conn, 422)
    end
  end

  describe "GET /api/chat/events" do
    test "streams SSE with correct headers and init frame", %{conn: conn} do
      conn = get(conn, ~p"/api/chat/events?once=true")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/event-stream"
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert conn.state == :chunked
      assert conn.resp_body =~ "data: "
      assert conn.resp_body =~ "\"type\":\"init\""
    end
  end
end
