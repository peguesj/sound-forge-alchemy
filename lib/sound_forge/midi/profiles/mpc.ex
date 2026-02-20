defmodule SoundForge.MIDI.Profiles.MPC do
  @moduledoc """
  Hardware-specific MIDI mappings for Akai MPC devices.

  Supports MPC One, MPC Live, MPC Studio Mk2, and MPC Key models.
  Provides pad-to-stem trigger mappings (notes 36-51), Q-Link knob
  CC mappings for stem volumes, transport button mappings, and sysex
  commands for pad LED color feedback.
  """

  @type model :: :mpc_one | :mpc_live | :mpc_studio_mk2 | :mpc_key
  @type color :: :red | :green | :blue | :yellow | :purple | :cyan | :white | :off

  @models %{
    mpc_one: "MPC One",
    mpc_live: "MPC Live",
    mpc_studio_mk2: "MPC Studio Mk2",
    mpc_key: "MPC Key"
  }

  # Pad notes: 16 pads mapped to MIDI notes 36-51
  @pad_notes Enum.to_list(36..51)

  # Q-Link knob CC numbers per model
  # MPC One/Live/Key use CCs 16-19, Studio Mk2 uses CCs 20-23
  @qlink_ccs %{
    mpc_one: [16, 17, 18, 19],
    mpc_live: [16, 17, 18, 19],
    mpc_studio_mk2: [20, 21, 22, 23],
    mpc_key: [16, 17, 18, 19]
  }

  # Transport button CC numbers
  @transport %{
    play: 118,
    stop: 117,
    rec: 119
  }

  # Sysex header per model (F0 47 00 <device_id> ... F7)
  @sysex_device_ids %{
    mpc_one: 0x40,
    mpc_live: 0x3A,
    mpc_studio_mk2: 0x3B,
    mpc_key: 0x41
  }

  @colors %{
    off: {0, 0, 0},
    red: {127, 0, 0},
    green: {0, 127, 0},
    blue: {0, 0, 127},
    yellow: {127, 127, 0},
    purple: {127, 0, 127},
    cyan: {0, 127, 127},
    white: {127, 127, 127}
  }

  @doc """
  Identifies the MPC model from a MIDI device name string.

  Returns `{:ok, model}` if the device name matches a known MPC device,
  or `:unknown` otherwise.

  ## Examples

      iex> SoundForge.MIDI.Profiles.MPC.detect("Akai MPC One")
      {:ok, :mpc_one}

      iex> SoundForge.MIDI.Profiles.MPC.detect("Some Other Controller")
      :unknown
  """
  @spec detect(String.t()) :: {:ok, model()} | :unknown
  def detect(device_name) when is_binary(device_name) do
    normalized = String.downcase(device_name)

    cond do
      String.contains?(normalized, "mpc studio") ->
        {:ok, :mpc_studio_mk2}

      String.contains?(normalized, "mpc key") ->
        {:ok, :mpc_key}

      String.contains?(normalized, "mpc live") ->
        {:ok, :mpc_live}

      String.contains?(normalized, "mpc one") ->
        {:ok, :mpc_one}

      true ->
        :unknown
    end
  end

  @doc """
  Returns sysex bytes for setting pad LED color on the given MPC model.

  ## Parameters

    - `model` - The MPC model atom
    - `pad_number` - Pad index 0-15
    - `color` - Color atom (`:red`, `:green`, `:blue`, `:yellow`, `:purple`, `:cyan`, `:white`, `:off`)

  ## Examples

      iex> SoundForge.MIDI.Profiles.MPC.pad_color(:mpc_one, 0, :red)
      [0xF0, 0x47, 0x00, 0x40, 0x65, 0x00, 0x04, 0x00, 0x7F, 0x00, 0x00, 0xF7]
  """
  @spec pad_color(model(), non_neg_integer(), color()) :: [non_neg_integer()]
  def pad_color(model, pad_number, color)
      when is_atom(model) and pad_number in 0..15 and is_atom(color) do
    device_id = Map.fetch!(@sysex_device_ids, model)
    {r, g, b} = Map.fetch!(@colors, color)

    # Sysex: F0 47 00 <device_id> 65 00 04 <pad> <r> <g> <b> F7
    [0xF0, 0x47, 0x00, device_id, 0x65, 0x00, 0x04, pad_number, r, g, b, 0xF7]
  end

  @doc """
  Returns a list of mapping attribute maps for the given MPC model and user.

  These are ready to pass to `SoundForge.MIDI.Mappings.create_mapping/1`.
  Includes:
  - 16 pad mappings (notes 36-51) for stem slot triggers with velocity sensitivity
  - 4 Q-Link knob mappings for stem volume control
  - 3 transport button mappings (play, stop, rec/bpm_tap)
  """
  @spec default_mappings(model(), binary()) :: [map()]
  def default_mappings(model, user_id) when is_atom(model) and is_binary(user_id) do
    device_name = Map.fetch!(@models, model)

    pad_mappings(user_id, device_name) ++
      qlink_mappings(model, user_id, device_name) ++
      transport_mappings(user_id, device_name)
  end

  @doc """
  Returns the list of supported MPC model atoms.
  """
  @spec supported_models() :: [model()]
  def supported_models, do: Map.keys(@models)

  @doc """
  Returns the human-readable name for a model atom.
  """
  @spec model_name(model()) :: String.t()
  def model_name(model), do: Map.fetch!(@models, model)

  @doc """
  Returns the pad MIDI note numbers (36-51).
  """
  @spec pad_notes() :: [non_neg_integer()]
  def pad_notes, do: @pad_notes

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
        action: :stem_solo,
        params: %{"stem_slot" => index, "velocity_sensitive" => true}
      }
    end)
  end

  defp qlink_mappings(model, user_id, device_name) do
    ccs = Map.fetch!(@qlink_ccs, model)

    ccs
    |> Enum.with_index()
    |> Enum.map(fn {cc, stem_index} ->
      %{
        user_id: user_id,
        device_name: device_name,
        midi_type: :cc,
        channel: 0,
        number: cc,
        action: :stem_volume,
        params: %{"stem_index" => stem_index}
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
        number: @transport.rec,
        action: :bpm_tap,
        params: %{}
      }
    ]
  end
end
