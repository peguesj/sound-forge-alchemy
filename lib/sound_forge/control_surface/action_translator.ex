defmodule SoundForge.ControlSurface.ActionTranslator do
  @moduledoc """
  Translates vendor-specific controller actions to SFA application actions.

  Different DJ software uses different naming conventions for the same actions.
  This module normalizes external action names into SFA action atoms.

  ## Examples

      # Traktor TSI
      ActionTranslator.translate("Deck A Play") #=> {:ok, :dj_play, %{deck: "1"}}
      ActionTranslator.translate("Crossfader") #=> {:ok, :dj_crossfader, %{}}

      # Rekordbox
      ActionTranslator.translate("PLAY_PAUSE_DECK_1") #=> {:ok, :dj_play, %{deck: "1"}}
      ActionTranslator.translate("CROSSFADER") #=> {:ok, :dj_crossfader, %{}}

      # TouchOSC (OSC address patterns)
      ActionTranslator.translate("/deck/1/play") #=> {:ok, :dj_play, %{deck: "1"}}

  ## Supported Actions

  See `SoundForge.MIDI.Mapping.actions/0` for the full list of SFA actions:

    - `:play`, `:stop` - Transport control
    - `:stem_solo`, `:stem_mute`, `:stem_volume` - Stem mixing
    - `:dj_play`, `:dj_cue`, `:dj_crossfader` - DJ mode
    - `:pad_trigger`, `:pad_volume` - Chromatic pads

  ## Roadmap (Wave 2)

  This module is a stub for US-012 (Wave 1). Wave 2 will implement:

    1. TSI action dictionary - map Traktor action strings to SFA actions
    2. Rekordbox action dictionary - map Rekordbox XML action names
    3. Parameter extraction - parse deck numbers, stem indices from action names
    4. Fuzzy matching - handle vendor variations ("PlayPause" vs "Play/Pause")
  """

  @doc """
  Translate a vendor-specific action string to an SFA action atom and params.

  Returns `{:ok, action, params}` or `{:error, :unknown_action}`.
  """
  @spec translate(String.t()) :: {:ok, atom(), map()} | {:error, term()}
  def translate(_action_string) do
    # Stub — Wave 2 will add translation dictionaries
    {:error, :not_implemented}
  end

  @doc """
  Detect the vendor/format of an action string.

  Returns `:traktor`, `:rekordbox`, `:touchosc`, `:generic`, or `:unknown`.
  """
  @spec detect_vendor(String.t()) :: atom()
  def detect_vendor(action_string) do
    cond do
      String.starts_with?(action_string, "/") -> :touchosc
      String.contains?(action_string, "Deck") -> :traktor
      String.contains?(action_string, "DECK") -> :rekordbox
      true -> :unknown
    end
  end

  @doc """
  Translate a Traktor action string to SFA action.

  ## Traktor Action Examples

    - "Deck A Play" -> `:dj_play` (deck 1)
    - "Deck B Cue" -> `:dj_cue` (deck 2)
    - "Crossfader" -> `:dj_crossfader`
    - "Master Volume" -> `:stem_volume` (target: master)
  """
  @spec translate_traktor(String.t()) :: {:ok, atom(), map()} | {:error, term()}
  def translate_traktor(_action) do
    # Wave 2 implementation
    {:error, :not_implemented}
  end

  @doc """
  Translate a Rekordbox action string to SFA action.

  ## Rekordbox Action Examples

    - "PLAY_PAUSE_DECK_1" -> `:dj_play` (deck 1)
    - "HOT_CUE_1_DECK_1" -> `:dj_cue` (deck 1, slot 1)
    - "CROSSFADER" -> `:dj_crossfader`
  """
  @spec translate_rekordbox(String.t()) :: {:ok, atom(), map()} | {:error, term()}
  def translate_rekordbox(_action) do
    # Wave 2 implementation
    {:error, :not_implemented}
  end

  @doc """
  Translate a TouchOSC address pattern to SFA action.

  ## TouchOSC Address Examples

    - "/deck/1/play" -> `:dj_play` (deck 1)
    - "/stem/1/volume" -> `:stem_volume` (stem 1)
    - "/transport/play" -> `:play`
  """
  @spec translate_touchosc(String.t()) :: {:ok, atom(), map()} | {:error, term()}
  def translate_touchosc(_address) do
    # Wave 2 implementation
    {:error, :not_implemented}
  end
end
