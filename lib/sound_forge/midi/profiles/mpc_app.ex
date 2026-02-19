defmodule SoundForge.MIDI.Profiles.MPCApp do
  @moduledoc """
  MIDI profile for Akai MPC software applications.

  Detects and maps MPC Beats, MPC 2.0 Software, and iMPC Pro 2
  when they appear as virtual MIDI sources.
  """

  @type app_type :: :mpc_beats | :mpc_2_software | :impc_pro_2

  @app_patterns [
    {~r/MPC Beats/i, :mpc_beats},
    {~r/MPC 2\.?0?\s*(Software)?/i, :mpc_2_software},
    {~r/MPC\s+Software/i, :mpc_2_software},
    {~r/iMPC Pro/i, :impc_pro_2},
    {~r/iMPC/i, :impc_pro_2}
  ]

  # Virtual pad notes (same layout as hardware: notes 36-51)
  @pad_notes Enum.to_list(36..51)

  # Virtual Q-Link knob CCs
  @qlink_ccs [16, 17, 18, 19]

  # Transport CCs
  @transport %{
    play: 118,
    stop: 117,
    rec: 119
  }

  @doc "Detect if a MIDI port name matches an MPC app."
  @spec detect(String.t()) :: {:ok, app_type()} | :no_match
  def detect(port_name) when is_binary(port_name) do
    Enum.find_value(@app_patterns, :no_match, fn {pattern, app_type} ->
      if Regex.match?(pattern, port_name), do: {:ok, app_type}
    end)
  end

  @doc "Return default mappings for detected MPC app."
  @spec default_mappings(app_type()) :: [map()]
  def default_mappings(app_type) do
    pad_mappings(app_type) ++ knob_mappings(app_type) ++ transport_mappings(app_type)
  end

  @doc "Check for MIDI Multi mode (MPC v2.8+ firmware feature)."
  @spec multi_mode?(String.t()) :: boolean()
  def multi_mode?(port_name) do
    # Multi mode shows as multiple ports: "MPC Port A", "MPC Port B", etc.
    Regex.match?(~r/MPC\s+Port\s+[A-D]/i, port_name)
  end

  @doc "Get the multi-port channel for a given port name."
  @spec multi_port_channel(String.t()) :: {:ok, 1..4} | :not_multi
  def multi_port_channel(port_name) do
    case Regex.run(~r/MPC\s+Port\s+([A-D])/i, port_name) do
      [_, letter] ->
        channel = letter |> String.upcase() |> String.to_charlist() |> hd() |> Kernel.-(64)
        {:ok, channel}

      _ ->
        :not_multi
    end
  end

  # -- Private --

  defp pad_mappings(_app_type) do
    @pad_notes
    |> Enum.with_index(1)
    |> Enum.map(fn {note, idx} ->
      %{
        midi_type: :note_on,
        midi_channel: 10,
        midi_value: note,
        action: :stem_trigger,
        action_target: "pad_#{idx}",
        label: "Pad #{idx}"
      }
    end)
  end

  defp knob_mappings(_app_type) do
    @qlink_ccs
    |> Enum.with_index(1)
    |> Enum.map(fn {cc, idx} ->
      %{
        midi_type: :cc,
        midi_channel: 1,
        midi_value: cc,
        action: :stem_volume,
        action_target: "stem_#{idx}",
        label: "Q-Link #{idx}"
      }
    end)
  end

  defp transport_mappings(_app_type) do
    Enum.map(@transport, fn {action, cc} ->
      %{
        midi_type: :cc,
        midi_channel: 1,
        midi_value: cc,
        action: action,
        action_target: nil,
        label: "Transport #{action}"
      }
    end)
  end
end
