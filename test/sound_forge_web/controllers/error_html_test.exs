defmodule SoundForgeWeb.ErrorHTMLTest do
  use SoundForgeWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    result = render_to_string(SoundForgeWeb.ErrorHTML, "404", "html", [])
    assert result =~ "404"
    assert result =~ "Page not found"
    assert result =~ "Back to Library"
  end

  test "renders 500.html" do
    result = render_to_string(SoundForgeWeb.ErrorHTML, "500", "html", [])
    assert result =~ "500"
    assert result =~ "Something went wrong"
    assert result =~ "Back to Library"
  end
end
