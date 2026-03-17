# Sample Library Acquisition

Scripts and tools for importing sample packs into Sound Forge Alchemy.

## Quick Start

### Via Mix Task

```bash
# Validate a directory (dry run)
mix sample_library.acquire --path /path/to/samples --dry-run

# Import via Mix task (generates instructions)
mix sample_library.acquire --path /path/to/samples
```

### Via Elixir Console

```elixir
# 1. Create a SamplePack record
{:ok, pack} = SoundForge.SampleLibrary.create_pack(%{
  name: "My Sample Pack",
  source: "local",
  category: "drums",
  user_id: 1
})

# 2. (Optional) Generate a manifest from a directory
# Use the acquire.sh script to generate a manifest JSON, then:
{:ok, count} = SoundForge.SampleLibrary.import_from_manifest(pack, "/path/to/manifest.json")

# 3. Or use the background worker
{:ok, _job} = Oban.insert(SoundForge.Jobs.ManifestImportWorker.new(%{
  "pack_id" => pack.id,
  "manifest_path" => "/path/to/manifest.json"
}))
```

## Manifest Format

The manifest is a JSON array of file objects:

```json
[
  {
    "name": "kick_01.wav",
    "file_path": "/absolute/path/to/kick_01.wav",
    "bpm": 120.0,
    "key": "C",
    "category": "drums",
    "sample_type": "one_shot",
    "duration_ms": 250,
    "file_size": 44100,
    "tags": ["kick", "punchy", "dry"]
  }
]
```

Required fields: `name`, `file_path`
Optional fields: `bpm`, `key`, `category`, `sample_type`, `duration_ms`, `file_size`, `tags`
