---
title: Agent System
parent: Architecture
nav_order: 2
---

[Home](../index.md) > [Architecture](index.md) > Agent System

# Agent System

## Table of Contents

- [Overview](#overview)
- [Orchestrator](#orchestrator)
- [Specialist Agents](#specialist-agents)
- [Capability Map](#capability-map)
- [Instruction Routing](#instruction-routing)
- [Pipeline Execution](#pipeline-execution)
- [Context and Result Types](#context-and-result-types)
- [Usage Examples](#usage-examples)

---

## Overview

Sound Forge Alchemy includes a multi-agent system for music intelligence. Six specialist agents handle different domains of audio knowledge. A routing `Orchestrator` selects the best agent (or pipeline of agents) for any given instruction.

All agents communicate with configurable LLM backends — Anthropic, OpenAI, Google Gemini, Ollama, or Azure OpenAI. See [LLM Providers](llm-providers.md) for provider configuration.

---

## Orchestrator

**Module:** `SoundForge.Agents.Orchestrator`

The Orchestrator is the single entry point for all agentic work. It:

1. Inspects the incoming `Context.instruction` and optional `:task` hint
2. Selects the best specialist agent (or a pipeline of agents)
3. Executes the agent(s) sequentially or in parallel as needed
4. Merges and returns a unified `Result`

### Entry Points

```elixir
# Direct dispatch with task hint
Orchestrator.run(%Context{instruction: "Analyse the key", track_id: id}, task: :track_analysis)

# Auto-routing — instruction keyword matching
Orchestrator.run(%Context{instruction: "Plan a set with these 5 tracks", track_ids: ids})

# Sequential pipeline
Orchestrator.pipeline(%Context{...}, [TrackAnalysisAgent, MixPlanningAgent])
```

### `run/2` — Single Agent Dispatch

```
Orchestrator.run(%Context{}, opts) -> {:ok, %Result{}} | {:error, reason}
```

Options:
- `:task` — atom capability hint (e.g. `:track_analysis`) for direct dispatch. If omitted, the Orchestrator matches the instruction text against keyword patterns.

### `pipeline/3` — Sequential Multi-Agent Execution

```
Orchestrator.pipeline(%Context{}, [Module, ...], opts) -> {:ok, [%Result{}]} | {:error, reason}
```

Each agent receives the previous agent's result data merged into its context. The pipeline halts on the first error.

### `select_agent/2` — Preview Without Execution

```
Orchestrator.select_agent(%Context{}, opts) -> module()
```

Returns the module that would be selected without running it. Useful for UI previews and testing.

---

## Specialist Agents

### TrackAnalysisAgent

**Module:** `SoundForge.Agents.TrackAnalysisAgent`

Analyzes individual track characteristics. Default agent when no other matches.

**Capabilities:** `track_analysis`, `key_detection`, `bpm_detection`, `energy_analysis`, `harmonic_analysis`

**Instruction keywords:** `analys`, `key`, `bpm`, `tempo`, `chord`, `harmonic`, `genre`

### MixPlanningAgent

**Module:** `SoundForge.Agents.MixPlanningAgent`

Plans DJ sets, sequencing, and transition strategies.

**Capabilities:** `mix_planning`, `track_sequencing`, `transition_advice`, `key_compatibility`

**Instruction keywords:** `mix`, `set`, `playlist`, `transition`, `sequence`, `order`

### StemIntelligenceAgent

**Module:** `SoundForge.Agents.StemIntelligenceAgent`

Provides intelligence about separated stems — quality assessment, loop extraction advice, remixing guidance.

**Capabilities:** `stem_analysis`, `stem_recommendations`, `loop_extraction_advice`

**Instruction keywords:** `stem`, `vocal`, `drum`, `bass`, `isolat`

### CuePointAgent

**Module:** `SoundForge.Agents.CuePointAgent`

Detects and recommends cue points, loop regions, and structural markers.

**Capabilities:** `cue_point_analysis`, `loop_region_detection`, `drop_detection`

**Instruction keywords:** `cue`, `loop`, `drop`, `phrase`, `marker`

### MasteringAgent

**Module:** `SoundForge.Agents.MasteringAgent`

Provides mastering and mixing advice based on audio analysis data.

**Capabilities:** `mastering_advice`, `loudness_analysis`

**Instruction keywords:** `master`, `loud`, `lufs`, `dynamic`, `eq`, `compress`

### LibraryAgent

**Module:** `SoundForge.Agents.LibraryAgent`

Searches the track library, finds similar tracks, and curates playlists.

**Capabilities:** `library_search`, `track_recommendations`, `playlist_curation`

**Instruction keywords:** `librar`, `recommend`, `find`, `search`, `similar`, `tag`, `genre`

---

## Capability Map

The Orchestrator uses this ordered mapping for `:task` hint dispatch. First match wins.

| Capability | Agent |
|-----------|-------|
| `:track_analysis` | TrackAnalysisAgent |
| `:key_detection` | TrackAnalysisAgent |
| `:bpm_detection` | TrackAnalysisAgent |
| `:energy_analysis` | TrackAnalysisAgent |
| `:harmonic_analysis` | TrackAnalysisAgent |
| `:mix_planning` | MixPlanningAgent |
| `:track_sequencing` | MixPlanningAgent |
| `:transition_advice` | MixPlanningAgent |
| `:key_compatibility` | MixPlanningAgent |
| `:stem_analysis` | StemIntelligenceAgent |
| `:stem_recommendations` | StemIntelligenceAgent |
| `:loop_extraction_advice` | StemIntelligenceAgent |
| `:cue_point_analysis` | CuePointAgent |
| `:loop_region_detection` | CuePointAgent |
| `:drop_detection` | CuePointAgent |
| `:mastering_advice` | MasteringAgent |
| `:loudness_analysis` | MasteringAgent |
| `:library_search` | LibraryAgent |
| `:track_recommendations` | LibraryAgent |
| `:playlist_curation` | LibraryAgent |

---

## Instruction Routing

When no `:task` hint is provided, the Orchestrator matches the instruction text against regex patterns:

| Pattern | Agent |
|---------|-------|
| `\b(analys\|key\|bpm\|tempo\|chord\|harmonic\|genre)\b` | TrackAnalysisAgent |
| `\b(mix\|set\|playlist\|transition\|sequence\|order)\b` | MixPlanningAgent |
| `\b(stem\|vocal\|drum\|bass\|isolat)\b` | StemIntelligenceAgent |
| `\b(cue\|loop\|drop\|phrase\|marker)\b` | CuePointAgent |
| `\b(master\|loud\|lufs\|dynamic\|eq\|compress)\b` | MasteringAgent |
| `\b(librar\|recommend\|find\|search\|similar\|tag\|genre)\b` | LibraryAgent |

If no pattern matches, the default agent is `TrackAnalysisAgent`.

---

## Pipeline Execution

In a pipeline, each agent's result data is merged into the next agent's context:

```elixir
# Results chain: TrackAnalysisAgent result feeds into MixPlanningAgent context
Orchestrator.pipeline(ctx, [TrackAnalysisAgent, MixPlanningAgent])
```

Pipeline merging rules:
- If both `ctx.data` and `result.data` are maps, they are deep-merged with `Map.merge/2`
- If `ctx.data` is nil and `result.data` is a map, `ctx.data` is set to `result.data`
- If `result.data` is nil, context is unchanged

The pipeline returns `{:ok, [%Result{}, ...]}` with all intermediate results, or `{:error, reason}` on the first failure.

---

## Context and Result Types

### `SoundForge.Agents.Context`

```elixir
%Context{
  instruction: String.t(),    # Natural language instruction
  track_id: binary() | nil,   # Single track context
  track_ids: [binary()] | nil, # Multi-track context
  user_id: binary() | nil,    # User requesting the operation
  data: map() | nil           # Arbitrary context data (merged between pipeline stages)
}
```

### `SoundForge.Agents.Result`

```elixir
%Result{
  agent: module(),            # Agent that produced the result
  status: :ok | :error,       # Outcome
  content: String.t() | nil,  # Human-readable response
  data: map() | nil,          # Structured data (merged into next pipeline stage)
  tool_calls: [map()] | nil,  # Any tool calls made during execution
  tokens_used: integer() | nil # LLM token consumption
}
```

---

## Usage Examples

```elixir
# Analyze a single track's key and tempo
{:ok, result} = Orchestrator.run(
  %Context{instruction: "What key and tempo is this track?", track_id: track_id},
  task: :track_analysis
)
IO.puts(result.content)
# => "This track is in A minor at 128 BPM with moderate energy."

# Plan a DJ set from 5 tracks
{:ok, result} = Orchestrator.run(
  %Context{
    instruction: "Create an optimal track ordering for a progressive house set",
    track_ids: [id1, id2, id3, id4, id5]
  }
)

# Analysis pipeline: analyze then generate mastering advice
{:ok, [analysis_result, mastering_result]} = Orchestrator.pipeline(
  %Context{instruction: "Analyze and give mastering advice", track_id: track_id},
  [TrackAnalysisAgent, MasteringAgent]
)
```

---

## See Also

- [LLM Providers](llm-providers.md)
- [AI Agents Feature Guide](../features/ai-agents.md)
- [Architecture Overview](index.md)

---

[← Stack Details](stack.md) | [Next: LLM Providers →](llm-providers.md)
