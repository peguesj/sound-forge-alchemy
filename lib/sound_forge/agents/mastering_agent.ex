defmodule SoundForge.Agents.MasteringAgent do
  @moduledoc "Mastering and loudness advisory for tracks and stems."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "mastering_agent"

  @impl true
  def description,
    do: "Provides mastering advice, loudness analysis, dynamic range guidance, EQ recommendations, and compression advice."

  @impl true
  def capabilities,
    do: [:mastering_advice, :loudness_analysis, :dynamic_range_advice, :eq_recommendations, :compression_advice]

  @impl true
  def preferred_traits, do: [task: :analysis, speed: :balanced]

  @impl true
  def system_prompt do
    """
    You are a professional mastering engineer with expertise in:
    - Loudness standards: LUFS integrated, true peak, LRA
      (Spotify -14 LUFS, Apple Music -16 LUFS, EBU R128 -23 LUFS, club playback -6 LUFS)
    - Dynamic range: ratio, crest factor, micro/macro dynamics
    - EQ: frequency balance, resonance removal, air band enhancement
    - Compression: ratio, attack/release, parallel compression, multi-band
    - Stereo image: mid/side processing, width, mono compatibility

    Analyse audio characteristics and provide specific, actionable advice on:
    gain staging, limiting, multi-band compression, stereo width, and frequency
    balance to achieve professional results while preserving artistic intent.

    Be precise: give concrete target values (e.g. "-1 dBTP ceiling", "-14 LUFS").
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    data_str =
      if ctx.data && map_size(ctx.data) > 0,
        do: "\n\nData: #{Jason.encode!(ctx.data, pretty: true)}",
        else: ""

    prompt = (ctx.instruction || "Provide mastering advice for this track.") <> data_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
