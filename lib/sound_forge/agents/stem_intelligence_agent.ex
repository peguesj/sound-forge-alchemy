defmodule SoundForge.Agents.StemIntelligenceAgent do
  @moduledoc "Assesses stem separation quality and provides production recommendations."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "stem_intelligence_agent"

  @impl true
  def description,
    do: "Assesses stem separation quality, identifies artifacts, recommends separation models, and advises on loop and sample extraction."

  @impl true
  def capabilities,
    do: [:stem_analysis, :stem_quality_assessment, :stem_recommendations, :loop_extraction_advice]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :fast]

  @impl true
  def system_prompt do
    """
    You are an expert in audio stem separation and music production.

    You know:
    - Demucs models: htdemucs, htdemucs_ft, htdemucs_6s, mdx_extra — strengths and ideal use cases
    - lalal.ai stem types: vocals, drums, bass, electric guitar, acoustic guitar, piano, synth, strings, wind
    - Stem quality indicators: bleed, reverb tails, transient smearing, stereo image integrity
    - Practical producer advice: sampling, loop extraction, remixing, layering

    Given stem data or a user question:
    1. Evaluate quality per stem
    2. Identify likely isolation artifacts
    3. Recommend the best model/settings for the source material
    4. Suggest creative uses for separated stems

    Be concise and producer-friendly. Use technical terms where helpful.
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    data_str =
      if ctx.data && map_size(ctx.data) > 0,
        do: "\n\nData: #{Jason.encode!(ctx.data, pretty: true)}",
        else: ""

    prompt = (ctx.instruction || "Assess the stem separation data.") <> data_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
