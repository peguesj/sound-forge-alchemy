defmodule SoundForgeWeb.Live.Components.TrackDetailResponsiveTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.TrackDetailResponsive

  describe "track_detail_tabs/1" do
    test "renders tabs with default stems tab active" do
      html =
        render_component(&TrackDetailResponsive.track_detail_tabs/1,
          active_tab: :stems,
          track: %{title: "Test Track"}
        )

      assert html =~ "track-detail-tabs"
      assert html =~ "Stems"
      assert html =~ "Analysis"
      assert html =~ "Details"
    end

    test "renders analysis tab active" do
      html =
        render_component(&TrackDetailResponsive.track_detail_tabs/1,
          active_tab: :analysis,
          track: %{title: "Test Track"}
        )

      assert html =~ "border-purple-500"
    end
  end

  describe "responsive_album_art/1" do
    test "renders with nil src" do
      html = render_component(&TrackDetailResponsive.responsive_album_art/1, src: nil, alt: "Test")
      assert html =~ "rounded-lg"
    end

    test "renders with src" do
      html = render_component(&TrackDetailResponsive.responsive_album_art/1, src: "http://example.com/art.jpg", alt: "Album")
      assert html =~ "http://example.com/art.jpg"
    end
  end
end
