---
title: Functional Core
nav_order: 13
parent: Architecture
---
# Functional Core

## Overview

Sound Forge Alchemy follows a functional core / imperative shell architecture. Pure business logic -- URL parsing, model validation, feature validation, status transitions -- lives in modules with no side effects. These pure functions are composed by context modules (the "shell") that handle database operations, port communication, and PubSub broadcasts.

This document covers the pure logic modules: what they compute, how they are structured, and how to test them.

## Spotify URL Parser

The `SoundForge.Spotify.URLParser` module is a pure function module that extracts Spotify resource type and ID from URLs. It has no dependencies on the database, HTTP client, or application configuration.

### Implementation

```elixir
# lib/sound_forge/spotify/url_parser.ex
defmodule SoundForge.Spotify.URLParser do
  @moduledoc """
  Parses Spotify URLs to extract type and ID.
  Supports standard Spotify URLs for tracks, albums, and playlists.
  """

  @spotify_regex ~r{(?:https?://)?(?:open\.)?spotify\.com/(?:intl-\w+/)?(track|album|playlist)/([a-zA-Z0-9]+)}

  @spec parse(String.t()) ::
          {:ok, %{type: String.t(), id: String.t()}} | {:error, :invalid_spotify_url}
  def parse(url) when is_binary(url) do
    case Regex.run(@spotify_regex, url) do
      [_, type, id] -> {:ok, %{type: type, id: id}}
      _ -> {:error, :invalid_spotify_url}
    end
  end

  def parse(_), do: {:error, :invalid_spotify_url}
end
```

### URL Patterns Supported

The regex handles the following Spotify URL formats:

| Format | Example | Extracted |
|--------|---------|-----------|
| HTTPS with `open` subdomain | `https://open.spotify.com/track/abc123` | `%{type: "track", id: "abc123"}` |
| Without `https://` | `open.spotify.com/track/abc123` | `%{type: "track", id: "abc123"}` |
| Without `open` subdomain | `https://spotify.com/track/abc123` | `%{type: "track", id: "abc123"}` |
| With international locale | `https://open.spotify.com/intl-de/track/abc123` | `%{type: "track", id: "abc123"}` |
| Album URLs | `https://open.spotify.com/album/xyz789` | `%{type: "album", id: "xyz789"}` |
| Playlist URLs | `https://open.spotify.com/playlist/list456` | `%{type: "playlist", id: "list456"}` |
| With query parameters | `https://open.spotify.com/track/abc123?si=xxx&nd=1` | `%{type: "track", id: "abc123"}` |

The regex captures only alphanumeric characters for the ID (`[a-zA-Z0-9]+`), which naturally strips query parameters since `?` is not alphanumeric.

### Rejected Inputs

| Input | Result | Reason |
|-------|--------|--------|
| `"https://example.com/track/123"` | `{:error, :invalid_spotify_url}` | Not a Spotify domain |
| `"https://open.spotify.com/artist/abc"` | `{:error, :invalid_spotify_url}` | `artist` is not a supported type |
| `""` | `{:error, :invalid_spotify_url}` | Empty string |
| `nil` | `{:error, :invalid_spotify_url}` | Non-string input |
| `123` | `{:error, :invalid_spotify_url}` | Non-string input |

### Test Coverage

The URL parser has comprehensive test coverage in `test/sound_forge/spotify_test.exs`:

```elixir
# test/sound_forge/spotify_test.exs (URLParser tests)
describe "URLParser.parse/1" do
  test "parses valid track URL with https" do
    assert {:ok, %{type: "track", id: "abc123"}} =
             URLParser.parse("https://open.spotify.com/track/abc123")
  end

  test "parses valid track URL without https" do
    assert {:ok, %{type: "track", id: "xyz789"}} =
             URLParser.parse("open.spotify.com/track/xyz789")
  end

  test "parses valid album URL" do
    assert {:ok, %{type: "album", id: "album456"}} =
             URLParser.parse("https://open.spotify.com/album/album456")
  end

  test "parses valid playlist URL" do
    assert {:ok, %{type: "playlist", id: "playlist789"}} =
             URLParser.parse("https://open.spotify.com/playlist/playlist789")
  end

  test "parses URL with international locale" do
    assert {:ok, %{type: "track", id: "track123"}} =
             URLParser.parse("https://open.spotify.com/intl-de/track/track123")
  end

  test "parses URL without 'open' subdomain" do
    assert {:ok, %{type: "track", id: "track123"}} =
             URLParser.parse("https://spotify.com/track/track123")
  end

  test "returns error for invalid URL format" do
    assert {:error, :invalid_spotify_url} = URLParser.parse("https://example.com/track/123")
  end

  test "returns error for empty string" do
    assert {:error, :invalid_spotify_url} = URLParser.parse("")
  end

  test "returns error for non-string input" do
    assert {:error, :invalid_spotify_url} = URLParser.parse(nil)
    assert {:error, :invalid_spotify_url} = URLParser.parse(123)
  end

  test "returns error for Spotify URL with invalid type" do
    assert {:error, :invalid_spotify_url} =
             URLParser.parse("https://open.spotify.com/artist/abc123")
  end
end
```

These tests run with `async: true` because the module is pure -- no shared state, no database, no processes.

## Job Status Validation

### Current Implementation

Status validation currently relies on `Ecto.Enum` and `validate_inclusion/3` in each job schema's changeset:

```elixir
# Shared across DownloadJob, ProcessingJob, and AnalysisJob
@status_values [:queued, :downloading, :processing, :completed, :failed]

def changeset(job, attrs) do
  job
  |> cast(attrs, [:status, ...])
  |> validate_inclusion(:status, @status_values)
end
```

This validates that a status is a valid value but does not validate that a _transition_ is valid. For example, nothing currently prevents transitioning from `:completed` back to `:queued`.

### Planned: Status Transition Guard

A pure function module for validating status transitions:

```elixir
# Planned: lib/sound_forge/jobs/status.ex
defmodule SoundForge.Jobs.Status do
  @moduledoc """
  Pure functions for job status validation and transitions.
  No database access -- operates on values only.
  """

  @type status :: :queued | :downloading | :processing | :completed | :failed

  @valid_transitions %{
    queued: [:downloading, :processing, :failed],
    downloading: [:processing, :completed, :failed],
    processing: [:completed, :failed],
    completed: [],
    failed: []
  }

  @doc """
  Checks if a status transition is valid.

  ## Examples

      iex> Status.valid_transition?(:queued, :downloading)
      true

      iex> Status.valid_transition?(:completed, :queued)
      false

      iex> Status.valid_transition?(:failed, :processing)
      false
  """
  @spec valid_transition?(status(), status()) :: boolean()
  def valid_transition?(from, to) do
    to in Map.get(@valid_transitions, from, [])
  end

  @doc """
  Returns the list of valid next statuses from the given status.

  ## Examples

      iex> Status.valid_next_statuses(:queued)
      [:downloading, :processing, :failed]

      iex> Status.valid_next_statuses(:completed)
      []
  """
  @spec valid_next_statuses(status()) :: [status()]
  def valid_next_statuses(status) do
    Map.get(@valid_transitions, status, [])
  end

  @doc """
  Returns true if the status is a terminal state (no further transitions possible).

  ## Examples

      iex> Status.terminal?(:completed)
      true

      iex> Status.terminal?(:failed)
      true

      iex> Status.terminal?(:processing)
      false
  """
  @spec terminal?(status()) :: boolean()
  def terminal?(status) do
    valid_next_statuses(status) == []
  end

  @doc """
  Returns true if the status indicates active work is in progress.

  ## Examples

      iex> Status.active?(:downloading)
      true

      iex> Status.active?(:processing)
      true

      iex> Status.active?(:queued)
      false
  """
  @spec active?(status()) :: boolean()
  def active?(status) when status in [:downloading, :processing], do: true
  def active?(_), do: false
end
```

### Integration with Changesets

Once implemented, the status transition guard would be called from a custom changeset validation:

```elixir
# Planned addition to job changesets
def transition_changeset(job, new_status) do
  if SoundForge.Jobs.Status.valid_transition?(job.status, new_status) do
    changeset(job, %{status: new_status})
  else
    job
    |> change()
    |> add_error(:status, "invalid transition from #{job.status} to #{new_status}")
  end
end
```

### Test Pattern for Status Transitions

```elixir
# Planned: test/sound_forge/jobs/status_test.exs
defmodule SoundForge.Jobs.StatusTest do
  use ExUnit.Case, async: true

  alias SoundForge.Jobs.Status

  describe "valid_transition?/2" do
    test "queued can transition to downloading" do
      assert Status.valid_transition?(:queued, :downloading)
    end

    test "queued can transition to processing" do
      assert Status.valid_transition?(:queued, :processing)
    end

    test "queued can transition to failed (timeout, cancellation)" do
      assert Status.valid_transition?(:queued, :failed)
    end

    test "downloading can transition to completed" do
      assert Status.valid_transition?(:downloading, :completed)
    end

    test "downloading can transition to processing" do
      assert Status.valid_transition?(:downloading, :processing)
    end

    test "downloading can transition to failed" do
      assert Status.valid_transition?(:downloading, :failed)
    end

    test "processing can transition to completed" do
      assert Status.valid_transition?(:processing, :completed)
    end

    test "processing can transition to failed" do
      assert Status.valid_transition?(:processing, :failed)
    end

    test "completed cannot transition to anything" do
      refute Status.valid_transition?(:completed, :queued)
      refute Status.valid_transition?(:completed, :downloading)
      refute Status.valid_transition?(:completed, :processing)
      refute Status.valid_transition?(:completed, :failed)
    end

    test "failed cannot transition to anything" do
      refute Status.valid_transition?(:failed, :queued)
      refute Status.valid_transition?(:failed, :downloading)
      refute Status.valid_transition?(:failed, :processing)
      refute Status.valid_transition?(:failed, :completed)
    end

    test "no backward transitions" do
      refute Status.valid_transition?(:processing, :downloading)
      refute Status.valid_transition?(:downloading, :queued)
      refute Status.valid_transition?(:completed, :processing)
    end
  end

  describe "terminal?/1" do
    test "completed is terminal" do
      assert Status.terminal?(:completed)
    end

    test "failed is terminal" do
      assert Status.terminal?(:failed)
    end

    test "queued is not terminal" do
      refute Status.terminal?(:queued)
    end

    test "downloading is not terminal" do
      refute Status.terminal?(:downloading)
    end

    test "processing is not terminal" do
      refute Status.terminal?(:processing)
    end
  end
end
```

## Model Selection

### Demucs Model Configuration

The `SoundForge.Processing.Demucs` module provides a pure data source for available models:

```elixir
# lib/sound_forge/processing/demucs.ex
defmodule SoundForge.Processing.Demucs do
  @models [
    %{
      name: "htdemucs",
      description: "Hybrid Transformer Demucs - default 4-stem model (vocals, drums, bass, other)",
      stems: 4
    },
    %{
      name: "htdemucs_ft",
      description: "Fine-tuned Hybrid Transformer Demucs - higher quality, slower",
      stems: 4
    },
    %{
      name: "htdemucs_6s",
      description: "6-stem model (vocals, drums, bass, guitar, piano, other)",
      stems: 6
    },
    %{
      name: "mdx_extra",
      description: "MDX-Net Extra - alternative architecture, good for vocals",
      stems: 4
    }
  ]

  @spec list_models() :: [map()]
  def list_models, do: @models
end
```

### DemucsPort Model Validation

The `Audio.DemucsPort` validates models against a hardcoded list:

```elixir
# lib/sound_forge/audio/demucs_port.ex
@valid_models ~w(htdemucs htdemucs_ft mdx_extra)

def validate_model(model) when model in @valid_models, do: :ok
def validate_model(model), do: {:error, {:invalid_model, model}}

def valid_models, do: @valid_models
```

This is a pure guard function -- no side effects, no state. It uses a compile-time `when` guard for pattern matching against the module attribute.

### AnalyzerPort Feature Validation

Similarly, the `Audio.AnalyzerPort` validates requested features:

```elixir
# lib/sound_forge/audio/analyzer_port.ex
@valid_features ~w(tempo key energy spectral mfcc chroma all)

def validate_features(features) do
  invalid = Enum.reject(features, &(&1 in @valid_features))

  if Enum.empty?(invalid) do
    :ok
  else
    {:error, invalid}
  end
end

def valid_features, do: @valid_features
```

This function takes a list of feature names, filters out any that are not in the valid set, and returns either `:ok` or an error tuple containing the invalid feature names. It has no side effects.

### Test Patterns for Validation Functions

```elixir
# Testing model validation (pure, async-safe)
describe "DemucsPort.validate_model/1" do
  test "accepts htdemucs" do
    assert :ok = DemucsPort.validate_model("htdemucs")
  end

  test "accepts htdemucs_ft" do
    assert :ok = DemucsPort.validate_model("htdemucs_ft")
  end

  test "accepts mdx_extra" do
    assert :ok = DemucsPort.validate_model("mdx_extra")
  end

  test "rejects unknown models" do
    assert {:error, {:invalid_model, "unknown"}} = DemucsPort.validate_model("unknown")
  end

  test "rejects empty string" do
    assert {:error, {:invalid_model, ""}} = DemucsPort.validate_model("")
  end
end

# Testing feature validation (pure, async-safe)
describe "AnalyzerPort.validate_features/1" do
  test "accepts all valid features" do
    assert :ok = AnalyzerPort.validate_features(["tempo", "key", "energy"])
  end

  test "accepts single feature" do
    assert :ok = AnalyzerPort.validate_features(["tempo"])
  end

  test "accepts 'all' feature" do
    assert :ok = AnalyzerPort.validate_features(["all"])
  end

  test "rejects invalid features and returns them" do
    assert {:error, ["invalid_feature"]} =
             AnalyzerPort.validate_features(["tempo", "invalid_feature"])
  end

  test "accepts empty list" do
    assert :ok = AnalyzerPort.validate_features([])
  end
end
```

## Audio Feature Calculations

### Stem Count Derivation

A pure function to determine expected stem count from model name:

```elixir
# Derivable from SoundForge.Processing.Demucs.list_models/0
defp stems_for_model(model_name) do
  case Enum.find(Demucs.list_models(), &(&1.name == model_name)) do
    %{stems: count} -> count
    nil -> {:error, :unknown_model}
  end
end
```

### Stem Type Lists

The expected stem types for each model, derivable from the model configuration:

```elixir
# 4-stem models: htdemucs, htdemucs_ft, mdx_extra
@four_stem_types [:vocals, :drums, :bass, :other]

# 6-stem models: htdemucs_6s
@six_stem_types [:vocals, :drums, :bass, :guitar, :piano, :other]

def stem_types_for_model("htdemucs_6s"), do: @six_stem_types
def stem_types_for_model(_), do: @four_stem_types
```

### Feature Normalization

Audio analysis results from the Python script need normalization before storage. These are pure transformation functions:

```elixir
# Planned: lib/sound_forge/audio/features.ex
defmodule SoundForge.Audio.Features do
  @moduledoc """
  Pure functions for normalizing and transforming audio feature data
  returned from the Python analyzer.
  """

  @doc """
  Normalizes raw analyzer output into an AnalysisResult-compatible map.

  Takes the JSON-decoded output from analyzer.py and maps it to the
  column names used by the AnalysisResult schema.
  """
  @spec normalize(map()) :: map()
  def normalize(raw) when is_map(raw) do
    %{
      tempo: get_float(raw, "tempo"),
      key: get_string(raw, "key"),
      energy: get_float(raw, "energy"),
      spectral_centroid: get_float(raw, "spectral_centroid"),
      spectral_rolloff: get_float(raw, "spectral_rolloff"),
      zero_crossing_rate: get_float(raw, "zero_crossing_rate"),
      features: extract_extended_features(raw)
    }
  end

  defp get_float(map, key) do
    case Map.get(map, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value / 1
      _ -> nil
    end
  end

  defp get_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp extract_extended_features(raw) do
    # Pull out MFCC, chroma, and any non-standard fields
    standard_keys = ~w(tempo key energy spectral_centroid spectral_rolloff zero_crossing_rate)
    Map.drop(raw, standard_keys)
  end
end
```

## Spotify Client Behaviour

The `SoundForge.Spotify.Client` behaviour defines a pure interface contract with no implementation logic:

```elixir
# lib/sound_forge/spotify/client.ex
defmodule SoundForge.Spotify.Client do
  @callback fetch_track(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_album(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_playlist(String.t()) :: {:ok, map()} | {:error, term()}
end
```

This behaviour enables swapping the implementation via application config:

```elixir
# In SoundForge.Spotify context
defp spotify_client do
  Application.get_env(:sound_forge, :spotify_client, SoundForge.Spotify.HTTPClient)
end
```

In tests, Mox creates a mock implementation:

```elixir
# test/support setup
Mox.defmock(SoundForge.Spotify.MockClient, for: SoundForge.Spotify.Client)

# test/sound_forge/spotify_test.exs
expect(MockClient, :fetch_track, fn "track123" ->
  {:ok, %{"id" => "track123", "name" => "Test Song"}}
end)
```

## Changeset Validation as Pure Logic

Ecto changesets are pure data transformations. They do not touch the database -- that only happens when `Repo.insert/1` or `Repo.update/1` is called. This means changeset functions are testable without a database:

```elixir
# Pure changeset validation (no database needed)
test "Track changeset requires title" do
  changeset = Track.changeset(%Track{}, %{title: nil})
  refute changeset.valid?
  assert %{title: ["can't be blank"]} = errors_on(changeset)
end

test "Track changeset accepts valid attributes" do
  changeset = Track.changeset(%Track{}, %{title: "Test", artist: "Artist"})
  assert changeset.valid?
end

test "DownloadJob changeset validates progress range" do
  changeset = DownloadJob.changeset(%DownloadJob{}, %{track_id: Ecto.UUID.generate(), progress: 150})
  refute changeset.valid?
  assert %{progress: ["must be less than or equal to 100"]} = errors_on(changeset)
end

test "Stem changeset validates stem_type inclusion" do
  changeset = Stem.changeset(%Stem{}, %{
    track_id: Ecto.UUID.generate(),
    processing_job_id: Ecto.UUID.generate(),
    stem_type: :invalid_type
  })
  refute changeset.valid?
end
```

The `unique_constraint` on `spotify_id` and `foreign_key_constraint` on `track_id` are only enforced at the database level during `Repo.insert/update`, so those validations require `DataCase` tests with a real database connection.

## Testing Patterns for Pure Functions

### Async Tests

All pure function tests should use `async: true`:

```elixir
defmodule SoundForge.Spotify.URLParserTest do
  use ExUnit.Case, async: true
  # No database, no GenServer, no shared state
end
```

### Property-Based Testing Opportunities

The URL parser and validation functions are candidates for property-based testing:

```elixir
# Potential property test for URL parser
property "always extracts type and ID from well-formed URLs" do
  check all type <- member_of(["track", "album", "playlist"]),
            id <- string(:alphanumeric, min_length: 10, max_length: 30) do
    url = "https://open.spotify.com/#{type}/#{id}"
    assert {:ok, %{type: ^type, id: ^id}} = URLParser.parse(url)
  end
end

# Potential property test for feature validation
property "validate_features accepts any subset of valid features" do
  check all features <- list_of(member_of(AnalyzerPort.valid_features()), min_length: 1) do
    assert :ok = AnalyzerPort.validate_features(features)
  end
end
```

### Data-Driven Tests

Validation functions work well with data-driven test patterns:

```elixir
@valid_urls [
  {"https://open.spotify.com/track/abc123", %{type: "track", id: "abc123"}},
  {"spotify.com/album/xyz", %{type: "album", id: "xyz"}},
  {"https://open.spotify.com/intl-fr/playlist/list1", %{type: "playlist", id: "list1"}}
]

for {url, expected} <- @valid_urls do
  test "parses #{url}" do
    assert {:ok, unquote(Macro.escape(expected))} = URLParser.parse(unquote(url))
  end
end

@invalid_urls [
  "",
  "not a url",
  "https://example.com/track/123",
  "https://open.spotify.com/artist/abc",
  "https://open.spotify.com/show/abc"
]

for url <- @invalid_urls do
  test "rejects #{inspect(url)}" do
    assert {:error, :invalid_spotify_url} = URLParser.parse(unquote(url))
  end
end
```

## Summary of Pure Modules

| Module | Pure Functions | Side Effects |
|--------|--------------|--------------|
| `Spotify.URLParser` | `parse/1` | None |
| `Spotify.Client` | Behaviour only (no functions) | N/A |
| `Processing.Demucs` | `list_models/0` | None (compile-time data) |
| `Audio.DemucsPort` | `validate_model/1`, `valid_models/0` | `separate/2` uses GenServer + Port |
| `Audio.AnalyzerPort` | `validate_features/1`, `valid_features/0` | `analyze/2` uses GenServer + Port |
| `Music.Track` | `changeset/2` | None (changesets are pure) |
| `Music.DownloadJob` | `changeset/2` | None |
| `Music.ProcessingJob` | `changeset/2` | None |
| `Music.AnalysisJob` | `changeset/2` | None |
| `Music.Stem` | `changeset/2` | None |
| `Music.AnalysisResult` | `changeset/2` | None |
| `Jobs.Status` (planned) | `valid_transition?/2`, `terminal?/1`, `active?/1`, `valid_next_statuses/1` | None |
| `Audio.Features` (planned) | `normalize/1` | None |

All pure functions are safe to call from `async: true` tests, can be composed without worrying about ordering, and serve as the stable foundation upon which the imperative shell (context modules, workers, GenServers) is built.
