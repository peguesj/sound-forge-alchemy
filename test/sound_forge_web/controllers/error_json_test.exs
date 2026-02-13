defmodule SoundForgeWeb.ErrorJSONTest do
  use SoundForgeWeb.ConnCase, async: true

  test "renders 404" do
    assert SoundForgeWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert SoundForgeWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  test "includes request_id when conn has x-request-id header" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_resp_header("x-request-id", "test-req-123")

    result = SoundForgeWeb.ErrorJSON.render("404.json", %{conn: conn})
    assert result.request_id == "test-req-123"
    assert result.errors.detail == "Not Found"
  end

  test "omits request_id when no x-request-id header" do
    result = SoundForgeWeb.ErrorJSON.render("404.json", %{})
    refute Map.has_key?(result, :request_id)
  end
end
