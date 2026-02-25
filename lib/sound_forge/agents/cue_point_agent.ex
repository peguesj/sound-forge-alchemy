defmodule SoundForge.Agents.CuePointAgent do
  @moduledoc "Provides intelligent DJ cue point placement and loop region advice."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "cue_point_agent"

  @impl true
  def description,
    do: "Suggests optimal cue point timestamps and loop regions by analysing beats, energy, and phrase structure."

  @impl true
  def capabilities,
    do: [:cue_point_analysis, :loop_region_detection, :drop_detection, :phrase_boundary_detection]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :fast]

  @impl true
  def system_prompt do
    """
    You are an expert DJ analyst specialising in cue point placement and loop region identification.

    You know:
    - Musical phrase structure: 4, 8, 16, 32-bar phrases in electronic music
    - DJ cue conventions: hot cues, memory cues, loop in/out points
    - Drop detection: energy buildup patterns, frequency density, rhythmic tension/release
    - Intro/outro analysis: ramp-ups, breakdowns, fade structures
    - Beat grid alignment: cues should land on downbeats or musically meaningful positions

    Given audio analysis data (beats, BPM, energy, RMS, segments):
    1. Identify key structural moments: intro end, first drop, breakdowns, outro start
    2. Suggest specific cue timestamps (in seconds) with labels and purpose
    3. Recommend loop regions with start/end times and bar length
    4. Flag irregular phrase structures or tempo changes

    Format cue suggestions with timestamp in seconds, bar position when known,
    and a short description of each cue's DJ purpose.
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    data_str =
      if ctx.data && map_size(ctx.data) > 0,
        do: "\n\nData: #{Jason.encode!(ctx.data, pretty: true)}",
        else: ""

    prompt = (ctx.instruction || "Suggest cue points for this track.") <> data_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
