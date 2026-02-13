defmodule SoundForgeWeb.ErrorJSONTest do
  use SoundForgeWeb.ConnCase, async: true

  test "renders 401" do
    result = SoundForgeWeb.ErrorJSON.render("401.json", %{})
    assert result.error == "Unauthorized"
  end

  test "renders 403" do
    result = SoundForgeWeb.ErrorJSON.render("403.json", %{})
    assert result.error == "Forbidden"
  end

  test "renders 404" do
    result = SoundForgeWeb.ErrorJSON.render("404.json", %{})
    assert result.error == "Not Found"
  end

  test "renders 500" do
    result = SoundForgeWeb.ErrorJSON.render("500.json", %{})
    assert result.error == "Internal Server Error"
  end

  test "renders unknown status via fallback" do
    result = SoundForgeWeb.ErrorJSON.render("418.json", %{})
    assert result.errors.detail == "I'm a teapot"
  end
end
