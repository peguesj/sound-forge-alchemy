defmodule SoundForge.Agents.MixPlanningAgent do
  @moduledoc "Plans DJ set sequences and mix transitions."

  use SoundForge.Agents.Agent

  @impl true
  def name, do: "mix_planning_agent"

  @impl true
  def description,
    do: "Plans DJ set sequences and mix transitions using Camelot key compatibility, energy flow, and BPM alignment."

  @impl true
  def capabilities,
    do: [:mix_planning, :track_sequencing, :transition_advice, :energy_flow, :key_compatibility]

  @impl true
  def preferred_traits, do: [task: :generation, speed: :balanced]

  @impl true
  def system_prompt do
    """
    You are an expert DJ and mix planning assistant with deep knowledge of harmonic mixing.

    - Sequence tracks for optimal harmonic flow using the Camelot wheel
    - Manage energy curves: tension → peak → comedown
    - Suggest BPM alignment strategies (tempo-match, half-time, double-time)
    - Provide per-transition advice: cue points, loop lengths, effects, EQ moves
    - Flag key incompatibilities or large BPM jumps as warnings

    Camelot wheel: 1B=C/1A=Am, 2B=G/2A=Em, 3B=D/3A=Bm, 4B=A/4A=F#m,
    5B=E/5A=C#m, 6B=B/6A=G#m, 7B=F#/7A=Ebm, 8B=Db/8A=Bbm,
    9B=Ab/9A=Fm, 10B=Eb/10A=Cm, 11B=Bb/11A=Gm, 12B=F/12A=Dm.
    Compatible: same position, ±1 number (same letter), or same number opposite letter.

    Return an ordered track list with concise transition notes (1-3 sentences each).
    Use JSON when a machine-readable plan is requested.
    """
  end

  @impl true
  def run(%Context{} = ctx, opts) do
    tracks_str =
      cond do
        ctx.track_ids && ctx.track_ids != [] && ctx.data ->
          tracks =
            Enum.map(ctx.track_ids, fn id ->
              meta = Map.get(ctx.data, id, Map.get(ctx.data, to_string(id), %{}))
              %{"track_id" => id, "metadata" => meta}
            end)

          "\n\nTracks:\n```json\n#{Jason.encode!(tracks, pretty: true)}\n```"

        ctx.data && map_size(ctx.data) > 0 ->
          "\n\nData:\n```json\n#{Jason.encode!(ctx.data, pretty: true)}\n```"

        true ->
          ""
      end

    prompt = (ctx.instruction || "Create a mix plan for the provided tracks.") <> tracks_str
    messages = format_messages(nil, [%{"role" => "user", "content" => prompt}])

    case call_llm(ctx.user_id, messages, opts) do
      {:ok, %Response{} = response} ->
        {:ok, Result.ok(__MODULE__, response.content, usage: response.usage)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
