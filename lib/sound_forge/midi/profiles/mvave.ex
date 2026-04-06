defmodule SoundForge.MIDI.Profiles.MVAVE do
  @moduledoc """
  Hardware-specific MIDI mappings for M-VAVE SMK-25 / Chord+ controllers.

  The M-VAVE is a compact 16-pad controller with 8 knobs in two rows of 4
  (Rate, Tempo, Swing, Latch per row) and a bottom transport button row.

  Default MIDI mapping (factory firmware):
  - Pads: Note On/Off, notes 36–51, channel 0
  - Knobs row 1 (Rate/Tempo/Swing/Latch): CC 1–4, channel 0
  - Knobs row 2: CC 5–8, channel 0
  - Transport: CC 20 (Play), CC 21 (Stop), CC 22 (Record), CC 23 (Loop)
  """

  @type model :: :mvave_standard

  @models %{
    mvave_standard: "M-VAVE"
  }

  # Pad notes: same standard as MPC (36-51)
  @pad_notes Enum.to_list(36..51)

  # Knob CC assignments: row1 = Rate/Tempo/Swing/Latch, row2 = additional controls
  @knob_ccs %{
    mvave_standard: %{
      row1: [1, 2, 3, 4],
      row2: [5, 6, 7, 8]
    }
  }

  # Transport CCs
  @transport %{
    play: 20,
    stop: 21,
    record: 22,
    loop: 23
  }

  # Knob labels per row
  @knob_labels_row1 ["Rate", "Tempo", "Swing", "Latch"]
  @knob_labels_row2 ["Knob 5", "Knob 6", "Knob 7", "Knob 8"]

  @doc """
  Identifies the M-VAVE from a MIDI device name string.

  ## Examples

      iex> SoundForge.MIDI.Profiles.MVAVE.detect("M-VAVE")
      {:ok, :mvave_standard}

      iex> SoundForge.MIDI.Profiles.MVAVE.detect("Unknown Controller")
      :unknown
  """
  @spec detect(String.t()) :: {:ok, model()} | :unknown
  def detect(device_name) when is_binary(device_name) do
    normalized = String.downcase(device_name)

    cond do
      String.contains?(normalized, "m-vave") ->
        {:ok, :mvave_standard}

      String.contains?(normalized, "mvave") ->
        {:ok, :mvave_standard}

      true ->
        :unknown
    end
  end

  @doc """
  Returns default mapping attrs for M-VAVE controller.

  Includes:
  - 16 pad mappings (notes 36–51) → pad_trigger
  - 4 row-1 knob mappings (CC 1–4) → stem_volume stems 0–3
  - 4 row-2 knob mappings (CC 5–8) → stem_volume stems 4–7
  - Transport: play, stop, bpm_tap, dj_loop_toggle
  """
  @spec default_mappings(model(), integer() | binary()) :: [map()]
  def default_mappings(model, user_id)
      when is_atom(model) and (is_integer(user_id) or is_binary(user_id)) do
    device_name = Map.fetch!(@models, model)
    ccs = Map.fetch!(@knob_ccs, model)

    pad_mappings(user_id, device_name) ++
      knob_mappings(ccs.row1, 0, user_id, device_name) ++
      knob_mappings(ccs.row2, 4, user_id, device_name) ++
      transport_mappings(user_id, device_name)
  end

  @doc "Returns the list of supported M-VAVE model atoms."
  @spec supported_models() :: [model()]
  def supported_models, do: Map.keys(@models)

  @doc "Returns the human-readable name for a model atom."
  @spec model_name(model()) :: String.t()
  def model_name(model), do: Map.fetch!(@models, model)

  @doc "Returns the physical layout of the M-VAVE for SVG rendering."
  @spec layout(model()) :: map()
  def layout(:mvave_standard) do
    %{
      device_name: "M-VAVE",
      pads: Enum.map(0..15, fn i -> %{index: i, note: 36 + i, row: div(i, 4), col: rem(i, 4)} end),
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
      transport_buttons: [
        %{label: "Play", cc: @transport.play},
        %{label: "Stop", cc: @transport.stop},
        %{label: "Rec", cc: @transport.record},
        %{label: "Loop", cc: @transport.loop}
      ]
    }
  end

  @doc "Returns knob labels for row 1 (Rate/Tempo/Swing/Latch)."
  def knob_labels_row1, do: @knob_labels_row1

  @doc "Returns knob labels for row 2."
  def knob_labels_row2, do: @knob_labels_row2

  # -- Private --

  defp pad_mappings(user_id, device_name) do
    @pad_notes
    |> Enum.with_index()
    |> Enum.map(fn {note, index} ->
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :note_on,
        channel: 0,
        number: note,
        action: :pad_trigger,
        params: %{"pad_index" => index, "velocity_sensitive" => true}
      }
    end)
  end

  defp knob_mappings(ccs, stem_offset, user_id, device_name) do
    ccs
    |> Enum.with_index()
    |> Enum.map(fn {cc, i} ->
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: cc,
        action: :stem_volume,
        params: %{"stem_index" => stem_offset + i}
      }
    end)
  end

  defp transport_mappings(user_id, device_name) do
    [
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: @transport.play,
        action: :play,
        params: %{}
      },
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: @transport.stop,
        action: :stop,
        params: %{}
      },
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: @transport.record,
        action: :bpm_tap,
        params: %{}
      },
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: @transport.loop,
        action: :dj_loop_toggle,
        params: %{}
      }
    ]
  end
end
