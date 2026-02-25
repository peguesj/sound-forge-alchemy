defmodule SoundForge.Agents.TrackAnalysisAgent do
  @moduledoc "Analyses harmonic and rhythmic content of audio tracks."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "track_analysis_agent"

  @impl true
  def description,
    do: "Analyses harmonic and rhythmic content of tracks, detecting key, BPM, energy, chord progressions, and genre."

  @impl true
  def capabilities,
    do: [:track_analysis, :key_detection, :bpm_detection, :energy_analysis, :harmonic_analysis]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :balanced]

  @impl true
  def system_prompt do
    """
    You are an expert music analyst specialising in harmonic and rhythmic analysis.

    - Detect musical key and confidence level
    - Identify BPM and rhythmic feel (straight, swung, syncopated)
    - Assess energy profile: intro, verse, chorus, breakdown, outro
    - Analyse chord progressions and harmonic complexity
    - Identify genre and sub-genre with stylistic cues
    - Flag uncertainty explicitly (e.g. "likely F minor, confidence: medium")

    Be concise and precise. Give concrete values, not vague descriptions.
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    data_str =
      if ctx.data && map_size(ctx.data) > 0,
        do: "\n\nTrack data:\n```json\n#{Jason.encode!(ctx.data, pretty: true)}\n```",
        else: ""

    prompt = (ctx.instruction || "Analyse the following track data.") <> data_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
