defmodule SoundForgeWeb.Live.Components.PadAssignmentTest do
  use SoundForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SoundForgeWeb.Live.Components.PadAssignment

  describe "pad_grid/1" do
    test "renders 16 pads with no assignments" do
      html = render_component(&PadAssignment.pad_grid/1, assignments: %{}, stems: [])
      assert html =~ "pad-assignment"
      assert html =~ "Pad 1"
      assert html =~ "Pad 16"
      assert html =~ "Available Stems"
    end

    test "renders with assigned pads" do
      assignments = %{1 => %{stem_type: "vocals"}, 5 => %{stem_type: "drums"}}
      html = render_component(&PadAssignment.pad_grid/1, assignments: assignments, stems: [])
      assert html =~ "clear_pad"
    end

    test "renders available stems list" do
      stems = [
        %{id: "s1", name: "Vocals", type: "vocals"},
        %{id: "s2", name: "Drums", type: "drums"}
      ]

      html = render_component(&PadAssignment.pad_grid/1, assignments: %{}, stems: stems)
      assert html =~ "Available Stems"
      assert html =~ "Vocals"
    end
  end
end
