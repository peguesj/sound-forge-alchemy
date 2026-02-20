defmodule SoundForge.OSC.TouchOSCLayout do
  @moduledoc "Generates TouchOSC layout XML for the SFA stem mixer."

  @stem_count 8
  @stem_colors ["#3B82F6", "#EF4444", "#22C55E", "#A855F7", "#F59E0B", "#06B6D4", "#EC4899", "#6366F1"]

  @doc "Generate the complete TouchOSC layout XML."
  @spec generate_xml() :: binary()
  def generate_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <layout version="17" mode="0" orientation="horizontal">
      <tabpage name="Mixer" scalef="0.0" scalet="1.0">
        #{stem_faders()}
        #{mute_solo_buttons()}
        #{transport_controls()}
        #{bpm_display()}
        #{track_title()}
      </tabpage>
    </layout>
    """
    |> String.trim()
  end

  defp stem_faders do
    1..@stem_count
    |> Enum.map(fn i ->
      x = fader_x(i)
      color = Enum.at(@stem_colors, i - 1, "#FFFFFF")

      """
          <control name="stem_#{i}_vol" type="faderv" x="#{x}" y="60" w="60" h="400"
            color="#{color}" scalef="0.0" scalet="1.0"
            osc_cs="/stem/#{i}/volume">
            <values>
              <value key="x" default="0.75" />
            </values>
          </control>
          <label name="stem_#{i}_label" type="labelv" x="#{x}" y="470" w="60" h="30"
            color="#{color}" text="Stem #{i}" textSize="12" />
      """
    end)
    |> Enum.join()
  end

  defp mute_solo_buttons do
    1..@stem_count
    |> Enum.map(fn i ->
      x = fader_x(i)

      """
          <control name="stem_#{i}_mute" type="toggle" x="#{x}" y="510" w="28" h="28"
            color="#EF4444" osc_cs="/stem/#{i}/mute">
            <values><value key="x" default="0.0" /></values>
          </control>
          <control name="stem_#{i}_solo" type="toggle" x="#{x + 30}" y="510" w="28" h="28"
            color="#F59E0B" osc_cs="/stem/#{i}/solo">
            <values><value key="x" default="0.0" /></values>
          </control>
      """
    end)
    |> Enum.join()
  end

  defp transport_controls do
    """
        <control name="play" type="push" x="30" y="570" w="80" h="50"
          color="#22C55E" osc_cs="/transport/play">
          <values><value key="x" default="0.0" /></values>
        </control>
        <control name="stop" type="push" x="120" y="570" w="80" h="50"
          color="#EF4444" osc_cs="/transport/stop">
          <values><value key="x" default="0.0" /></values>
        </control>
        <control name="prev" type="push" x="210" y="570" w="60" h="50"
          color="#A855F7" osc_cs="/transport/prev">
          <values><value key="x" default="0.0" /></values>
        </control>
        <control name="next" type="push" x="280" y="570" w="60" h="50"
          color="#A855F7" osc_cs="/transport/next">
          <values><value key="x" default="0.0" /></values>
        </control>
    """
  end

  defp bpm_display do
    """
        <control name="bpm_display" type="label" x="370" y="570" w="80" h="50"
          color="#06B6D4" text="120" textSize="24" osc_cs="/bpm">
        </control>
    """
  end

  defp track_title do
    """
        <control name="track_title" type="label" x="460" y="570" w="200" h="50"
          color="#FFFFFF" text="No Track" textSize="16" osc_cs="/track/title">
        </control>
    """
  end

  defp fader_x(index), do: 30 + (index - 1) * 70
end
