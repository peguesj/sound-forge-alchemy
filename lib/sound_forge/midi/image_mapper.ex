defmodule SoundForge.MIDI.ImageMapper do
  @moduledoc """
  Analyzes an uploaded MIDI controller image using Claude vision to identify
  physical controls and suggest MIDI CC/note mappings.

  Returns a list of detected controls with suggested CC/note numbers that
  can be confirmed by the user and saved as MIDI mappings.
  """

  require Logger

  alias SoundForge.LLM.Providers.SystemProviders

  @system_prompt """
  You are a MIDI controller expert. Analyze the provided image of a MIDI controller
  and identify all physical controls visible.

  For each control, provide:
  - type: one of "knob", "fader", "pad", "button", "key", "wheel", "slider", "encoder"
  - label: any text or number printed near the control (null if none)
  - row: approximate row position (0 = top)
  - col: approximate column position (0 = left)
  - suggested_cc: for knobs/faders/sliders: suggest an appropriate MIDI CC number (1-127)
                  for pads: suggest a MIDI note number starting at 36
                  for buttons: suggest a CC or note
                  for keys: suggest note 0-127 (C4 = 60)

  Common MIDI CC assignments to follow when inferring:
  - CC 1: Modulation Wheel
  - CC 7: Volume
  - CC 10: Pan
  - CC 11: Expression
  - CC 64: Sustain Pedal
  - CC 74: Filter Cutoff
  - CC 71: Filter Resonance
  - Pad notes: 36, 37, 38... (General MIDI percussion)
  - Encoder/tempo: 14, 15

  Respond ONLY with a valid JSON array. No markdown, no explanation, just JSON:
  [{"type": "knob", "label": "VOLUME", "row": 0, "col": 0, "suggested_cc": 7}, ...]
  """

  @doc """
  Analyzes a base64-encoded controller image.

  Returns `{:ok, [%{type, label, row, col, suggested_cc}]}` on success,
  or `{:error, reason}`.

  `mime_type` should be "image/png", "image/jpeg", or "image/webp".
  """
  @spec analyze(String.t(), String.t()) ::
          {:ok, [map()]} | {:error, :no_provider | :parse_error | term()}
  def analyze(base64_data, mime_type \\ "image/png") do
    case SystemProviders.get_system_provider(:anthropic) do
      nil ->
        Logger.warning("ImageMapper: no Anthropic provider configured")
        {:error, :no_provider}

      provider ->
        call_vision_api(provider, base64_data, mime_type)
    end
  end

  defp call_vision_api(provider, base64_data, mime_type) do
    messages = [
      %{
        "role" => "user",
        "content" => [
          %{
            "type" => "image",
            "source" => %{
              "type" => "base64",
              "media_type" => mime_type,
              "data" => base64_data
            }
          },
          %{
            "type" => "text",
            "text" =>
              "Identify all MIDI controls in this controller image and return the JSON array as instructed."
          }
        ]
      }
    ]

    opts = [
      model: "claude-sonnet-4-20250514",
      max_tokens: 2048,
      temperature: 0.2,
      system: @system_prompt
    ]

    case SoundForge.LLM.Client.chat(provider, messages, opts) do
      {:ok, response} -> parse_controls(response.content)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_controls(raw_text) do
    json =
      raw_text
      |> String.trim()
      |> extract_json_array()

    case Jason.decode(json) do
      {:ok, controls} when is_list(controls) ->
        normalized = Enum.map(controls, &normalize_control/1)
        {:ok, normalized}

      {:ok, _} ->
        {:error, :parse_error}

      {:error, _} ->
        Logger.warning("ImageMapper: failed to parse response: #{String.slice(raw_text, 0, 200)}")
        {:error, :parse_error}
    end
  end

  defp extract_json_array(text) do
    # Strip markdown code fences if present
    text =
      text
      |> String.replace(~r/^```(?:json)?\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    # Find the first [ to last ]
    case {String.split(text, "[", parts: 2), String.split(text, "]")} do
      {[_, rest], parts} when length(parts) > 1 ->
        last = List.last(parts)
        "[" <> String.slice(rest, 0, String.length(rest) - String.length(last) - 1) <> "]"

      _ ->
        text
    end
  end

  defp normalize_control(raw) when is_map(raw) do
    %{
      type: parse_type(Map.get(raw, "type", "knob")),
      label: Map.get(raw, "label"),
      row: to_int(Map.get(raw, "row", 0)),
      col: to_int(Map.get(raw, "col", 0)),
      suggested_cc: to_int(Map.get(raw, "suggested_cc", 1)),
      confirmed: false
    }
  end

  defp parse_type(t) when is_binary(t) do
    case String.downcase(t) do
      "knob" -> :knob
      "fader" -> :fader
      "pad" -> :pad
      "button" -> :button
      "key" -> :key
      "wheel" -> :wheel
      "slider" -> :slider
      "encoder" -> :encoder
      _ -> :knob
    end
  end

  defp parse_type(_), do: :knob

  defp to_int(n) when is_integer(n), do: n
  defp to_int(f) when is_float(f), do: round(f)
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
  defp to_int(_), do: 0
end
