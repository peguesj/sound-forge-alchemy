defmodule SoundForgeWeb.Live.Components.StemMixerTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.StemMixer

  describe "stem_mixer/1" do
    test "renders empty mixer with no stems" do
      html = render_component(&StemMixer.stem_mixer/1, stems: [], volumes: %{})
      assert html =~ "stem-mixer"
    end

    test "renders stems with faders" do
      stems = [
        %{name: "vocals", id: "s1"},
        %{name: "drums", id: "s2"},
        %{name: "bass", id: "s3"}
      ]

      html =
        render_component(&StemMixer.stem_mixer/1,
          stems: stems,
          volumes: %{1 => 0.5, 2 => 0.8, 3 => 1.0}
        )

      assert html =~ "stem-mixer"
      assert html =~ "stem_mute"
      assert html =~ "stem_solo"
    end

    test "renders with default volumes" do
      stems = [%{name: "vocals", id: "s1"}]
      html = render_component(&StemMixer.stem_mixer/1, stems: stems, volumes: %{})
      assert html =~ "stem-mixer"
    end

    test "renders stems with type attribute using type-based color and label" do
      stems = [
        %{type: :vocals, id: "s1"},
        %{type: :drums, id: "s2"},
        %{type: :bass, id: "s3"},
        %{type: :melody, id: "s4"}
      ]

      html =
        render_component(&StemMixer.stem_mixer/1, stems: stems, volumes: %{1 => 0.5, 2 => 0.8})

      assert html =~ "stem-mixer"
      assert html =~ "Vocals"
      assert html =~ "Drums"
      assert html =~ "Bass"
      assert html =~ "bg-blue-500"
      assert html =~ "bg-red-500"
    end

    test "renders unknown stem type with fallback color" do
      stems = [%{id: "s1"}]
      html = render_component(&StemMixer.stem_mixer/1, stems: stems, volumes: %{})
      assert html =~ "stem-mixer"
      assert html =~ "Stem"
    end
  end
end
