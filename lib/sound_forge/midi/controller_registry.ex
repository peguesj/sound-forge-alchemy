defmodule SoundForge.MIDI.ControllerRegistry do
  @moduledoc """
  Registry of known MIDI controllers with their physical layouts.

  Each controller entry describes:
  - `id` — stable identifier atom
  - `name` — human-readable display name
  - `manufacturer` — brand
  - `detect` — name-match function for auto-detection
  - `pads` — list of %{index, note, row, col}
  - `knobs` — list of %{index, cc, label, row}
  - `buttons` — list of %{label, cc}
  - `svg_width` / `svg_height` — viewBox dimensions for the SVG schematic
  - `profile_module` — module implementing detect/1, default_mappings/2

  Used by MidiLive to render SVG controller visuals and auto-map presets.
  """

  alias SoundForge.MIDI.Profiles.{MPC, MVAVE}

  @doc """
  Returns the full list of known controllers.
  """
  @spec known_controllers() :: [map()]
  def known_controllers do
    [
      akai_mpc_live_ii(),
      mvave_standard()
    ]
  end

  @doc """
  Auto-detect a controller by device name. Returns the first matching
  registry entry, or nil if unrecognized.
  """
  @spec detect(String.t()) :: map() | nil
  def detect(device_name) when is_binary(device_name) do
    Enum.find(known_controllers(), fn ctrl ->
      ctrl.detect.(device_name)
    end)
  end

  @doc """
  Returns the registry entry for a specific controller id, or nil.
  """
  @spec get(atom()) :: map() | nil
  def get(id) when is_atom(id) do
    Enum.find(known_controllers(), &(&1.id == id))
  end

  # ---------------------------------------------------------------------------
  # Controller definitions
  # ---------------------------------------------------------------------------

  defp akai_mpc_live_ii do
    %{
      id: :akai_mpc_live_ii,
      name: "AKAI MPC Live II",
      manufacturer: "AKAI",
      svg_width: 360,
      svg_height: 230,
      profile_module: MPC,
      detect: fn name ->
        case MPC.detect(name) do
          {:ok, m} when m in [:mpc_live] -> true
          _ -> String.downcase(name) |> String.contains?("mpc")
        end
      end,
      pads:
        Enum.map(0..15, fn i ->
          # MPC pads: note 36-51, laid out 4x4 (row 0 = bottom row of pads)
          %{index: i, note: 36 + i, row: div(i, 4), col: rem(i, 4)}
        end),
      knobs: [
        %{index: 0, cc: 16, label: "Q1", row: 0},
        %{index: 1, cc: 17, label: "Q2", row: 0},
        %{index: 2, cc: 18, label: "Q3", row: 0},
        %{index: 3, cc: 19, label: "Q4", row: 0},
        %{index: 4, cc: 16, label: "Q5", row: 0},
        %{index: 5, cc: 17, label: "Q6", row: 0}
      ],
      buttons: [
        %{label: "Play", cc: 118},
        %{label: "Stop", cc: 117},
        %{label: "Rec", cc: 119},
        %{label: "Overdub", cc: 120}
      ]
    }
  end

  defp mvave_standard do
    %{
      id: :mvave_standard,
      name: "M-VAVE",
      manufacturer: "M-VAVE",
      svg_width: 300,
      svg_height: 210,
      profile_module: MVAVE,
      detect: fn name ->
        case MVAVE.detect(name) do
          {:ok, _} -> true
          :unknown -> false
        end
      end,
      pads:
        Enum.map(0..15, fn i ->
          %{index: i, note: 36 + i, row: div(i, 4), col: rem(i, 4)}
        end),
      knobs: [
        %{index: 0, cc: 1, label: "Rate", row: 0},
        %{index: 1, cc: 2, label: "Tempo", row: 0},
        %{index: 2, cc: 3, label: "Swing", row: 0},
        %{index: 3, cc: 4, label: "Latch", row: 0},
        %{index: 4, cc: 5, label: "Knob 5", row: 1},
        %{index: 5, cc: 6, label: "Knob 6", row: 1},
        %{index: 6, cc: 7, label: "Knob 7", row: 1},
        %{index: 7, cc: 8, label: "Knob 8", row: 1}
      ],
      buttons: [
        %{label: "Play", cc: 20},
        %{label: "Stop", cc: 21},
        %{label: "Rec", cc: 22},
        %{label: "Loop", cc: 23}
      ]
    }
  end
end
