---
title: MIDI Integration
parent: Features
nav_order: 6
---

[Home](../index.md) > [Features](index.md) > MIDI Integration

# MIDI Integration

Hardware MIDI controller support via Midiex, with learn mode, preset mappings, and universal controller detection.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Device Management](#device-management)
- [MIDI Learn Flow](#midi-learn-flow)
- [Mapping Storage](#mapping-storage)
- [Bug Fixes](#bug-fixes)
- [Universal Controller Preset](#universal-controller-preset)

---

## Overview

SFA connects to hardware MIDI controllers (Pioneer DDJ, Akai MPC, Traktor Kontrol, etc.) for hands-on control of DJ decks, DAW parameters, and chromatic pads. The MIDI subsystem is built on the `midiex` NIF library and consists of three supervised processes:

- **DeviceManager** -- scans and tracks connected MIDI ports (ETS-backed)
- **Dispatcher** -- routes incoming MIDI messages to subscribed LiveView processes via PubSub
- **Mappings** -- CRUD for control-to-action bindings stored in PostgreSQL

---

## Architecture

```
SoundForge.Supervisor
  |
  +-- SoundForge.MIDI.DeviceManager (GenServer + ETS)
  |     Scans Midiex.ports(), stores in :midi_devices ETS table
  |
  +-- SoundForge.MIDI.Dispatcher (GenServer)
  |     Subscribes to all input ports
  |     Broadcasts {:midi_message, port_id, msg} via PubSub
  |
  +-- SoundForge.MIDI.Mappings (context module)
        CRUD for midi_mappings table
```

Both DeviceManager and Dispatcher are children of `SoundForge.Supervisor` in `application.ex`, started after the Repo and PubSub.

---

## Device Management

`DeviceManager` uses ETS to store device state. Devices are identified by a **composite port_id** that combines direction and numeric index.

### Composite Port ID

`Midiex.ports()` returns both input and output ports that can share the same numeric `num` field. Using the raw `num` as the ETS key caused output ports to overwrite input ports, making all devices appear as `:output`.

The fix uses a composite key format:

```elixir
defp port_to_device(port) do
  direction = if port.direction == :input, do: "input", else: "output"
  port_id = "#{direction}:#{port.num}"

  %{
    port_id: port_id,
    name: port.name,
    direction: port.direction,
    num: port.num
  }
end
```

This guarantees unique ETS keys: `"input:0"`, `"output:0"`, `"input:1"`, etc.

---

## MIDI Learn Flow

MIDI Learn lets users bind physical controls to software actions without manual configuration.

### Sequence

1. User selects a device in the "Learn Device" dropdown (wrapped in a `<form phx-change="select_device">`)
2. User clicks the inline "Learn" button next to an action (e.g., `dj_play`) -- fires `start_learn_action`
3. LiveView subscribes to PubSub for that device's port_id
4. User presses a button/knob on the physical controller
5. Dispatcher broadcasts `{:midi_message, port_id, msg}` -- LiveView receives it and stores as `pending_learn`
6. User clicks "Save" -- fires `save_mapping` -- `Mappings.create_mapping/1` inserts a DB record

### Example

Pressing Play on an MPC Live II sends CC 118 on channel 0. After learn + save, this is stored as:

```elixir
%Mapping{
  user_id: 42,
  device_name: "MPC Live II",
  channel: 0,
  cc: 118,
  action: "dj_play",
  deck: "a"
}
```

---

## Mapping Storage

Mappings are stored in the `midi_mappings` table with an integer serial primary key (not UUID). The schema defaults are used -- no `@primary_key` override.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Auto-incrementing PK |
| `user_id` | integer | References `users` |
| `device_name` | string | Human-readable controller name |
| `channel` | integer | MIDI channel (0-15) |
| `cc` | integer | Control Change number |
| `note` | integer | Note number (for pads/keys) |
| `action` | string | Target action identifier |
| `deck` | string | Target deck ("a", "b", or nil) |

---

## Bug Fixes

The following issues were resolved in the MIDI subsystem:

### ETS Collision (DeviceManager)

**Problem:** `Midiex.ports()` returns both input and output ports sharing the same numeric `num` index. Using `num` as the ETS key caused output ports to overwrite input ports -- all devices appeared as `:output`.

**Fix:** Composite `port_id` (`"input:N"` / `"output:N"`) in `port_to_device/1`.

### Dispatcher Missing from Supervision Tree

**Problem:** `SoundForge.MIDI.Dispatcher` was defined but never added to `application.ex` children. The GenServer never started, so zero MIDI messages were dispatched.

**Fix:** Added `SoundForge.MIDI.Dispatcher` after `DeviceManager` in the supervision children list.

### phx-change Outside form

**Problem:** `<select phx-change="select_device">` elements not wrapped in a `<form>` tag silently failed. Phoenix LiveView requires `phx-change` inputs to be inside a `<form>`.

**Fix:** Wrapped each `<select phx-change>` in its own `<form phx-change="...">` element.

### resolve_user_id Guard

**Problem:** The `resolve_user_id` function had a guard `when is_binary(id)` that passed raw UUID bytes to an integer `user_id` column.

**Fix:** Changed guard to `when is_integer(id)`.

### Mapping Schema PK Mismatch

**Problem:** The `Mapping` schema declared `@primary_key {:id, :binary_id, autogenerate: true}` but the migration creates an integer serial PK. Ecto generated UUIDs that PostgreSQL rejected.

**Fix:** Removed `@primary_key` and `@foreign_key_type` overrides from `lib/sound_forge/midi/mapping.ex`, defaulting to integer. The `bank_id` field correctly stays `:binary_id` (references `sampler_banks` UUID PK).

---

## Universal Controller Preset

A planned feature to auto-detect connected controllers and apply a universal mapping preset.

### Architecture (Planned)

1. **ControllerRegistry** GenServer -- maintains a catalog of known controllers with fingerprint matching (device name patterns, port counts, CC ranges)
2. **AI AutoDetect** module -- when a new device connects, analyzes its MIDI output signature and matches against the registry
3. **Universal Preset UI** -- a settings page where users can review detected mappings, adjust individual bindings, and export/import presets as JSON

### Feature Branch

Development tracked on branch `feature/universal-controller-preset`.

---

## See Also

- [DJ / DAW Tools](dj-daw.md)
- [Architecture Overview](../architecture/index.md)
- [Database Schema](../architecture/database.md)

---

[← DJ / DAW Tools](dj-daw.md) | [Next: AI Agents →](ai-agents.md)
