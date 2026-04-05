# MIDI Device Subsystem — Runbook

**Application**: Sound Forge Alchemy (SFA)
**Stack**: Elixir/Phoenix, Midiex NIF, macOS ioreg
**Last reviewed**: 2026-03-30

---

## 1. Overview

| Module | Role |
|--------|------|
| `SoundForge.MIDI.DeviceManager` | GenServer. Polls Midiex every 2s. Broadcasts `"midi:devices"` PubSub events on change. Owns `:midi_devices` ETS table. |
| `SoundForge.MIDI.DeviceResearch` | GenServer. On-demand USB metadata lookup via macOS `ioreg`. Caches results in `:midi_device_research` ETS table. |
| `SoundForge.MIDI.GlobalBroadcaster` | Relays MIDI messages to PubSub subscribers. |

Only starts when `worker_mode == "full"`.

---

## 2. Architecture

### ETS Tables

| Table | Key | Value |
|-------|-----|-------|
| `:midi_devices` | `:devices` | `[%Midiex.MidiPort{}]` |
| `:midi_device_research` | `{vendor_id, product_id}` | `%{vendor: string, product: string}` |

### PubSub Topic

`"midi:devices"` — messages: `{:midi_devices_updated, devices}`

### Poll Interval

`@poll_interval_ms 2_000` — hard-coded, requires redeploy to change.

### `nif_ever_succeeded` Flag

`DeviceManager` suppresses disconnect broadcasts until the Midiex NIF has returned at least one successful result. This prevents spurious "all disconnected" events during NIF startup.

---

## 3. Checking Device Status

```elixir
# Current device list from ETS
:ets.lookup(:midi_devices, :devices)
# => [{:devices, [%Midiex.MidiPort{name: "Launchpad X", ...}]}]

# GenServer state
:sys.get_state(SoundForge.MIDI.DeviceManager)
# => %{devices: [...], nif_ever_succeeded: true, poll_ref: #Reference<...>}

# Is process alive?
Process.whereis(SoundForge.MIDI.DeviceManager)
# => #PID<...> or nil

# DeviceResearch cache
:ets.tab2list(:midi_device_research)
```

---

## 4. Hot-Plug Troubleshooting

### Device connected but not detected

**Cause**: `nif_ever_succeeded` is still `false` — NIF hasn't completed first successful poll.

```elixir
:sys.get_state(SoundForge.MIDI.DeviceManager)
# Check: nif_ever_succeeded: false
```

Wait 10s for 2-3 poll cycles. If still false, recompile Midiex:

```bash
mix deps.compile midiex --force
# Restart app
```

### Device shows disconnected when plugged in

```elixir
# Bypass DeviceManager — query NIF directly
Midiex.devices()
# If device appears here but not in ETS, next poll (≤2s) will pick it up

# Check poll timer is running
:sys.get_state(SoundForge.MIDI.DeviceManager).poll_ref
# nil = poll stopped → restart GenServer (Section 8)
```

---

## 5. Device Research

### ioreg lookup failure

```bash
/usr/sbin/ioreg -p IOUSB -l -w 0 | grep -A 5 "idVendor"
```

macOS only — not available in Docker/Linux containers. Devices fall back to raw `Midiex.MidiPort.name`.

### Adding a vendor to the lookup table

1. Find ID: `ioreg -p IOUSB -l -w 0 | grep "idVendor"`
2. Look up at https://usb-ids.gowdy.us/
3. Add to `@vendor_names` map in `device_research.ex`
4. Redeploy, then clear stale cache:

```elixir
:ets.delete(:midi_device_research, {0xXXXX, 0xYYYY})
SoundForge.MIDI.DeviceResearch.lookup_device(0xXXXX, 0xYYYY)
```

---

## 6. Common Failures

### Midiex NIF crash

```
** (ErlangError) Erlang error: :nif_not_loaded
```

```bash
ls _build/dev/lib/midiex/priv/   # check .so/.dylib exists
mix deps.compile midiex --force   # recompile
elixir --version                  # confirm OTP 24+
```

### DeviceManager not started (`worker_mode != "full"`)

```elixir
Application.get_env(:sound_forge, :worker_mode)
# => "web" or "gpu_worker"
```

Fix: `WORKER_MODE=full mix phx.server`

### PubSub not broadcasting

```elixir
Process.whereis(SoundForge.PubSub)   # must be alive
# Subscribe manually and test:
SoundForgeWeb.Endpoint.subscribe("midi:devices")
# Plug/unplug device, then:
flush()
```

Check that `nif_ever_succeeded` is `true` — broadcasts are suppressed until then.

---

## 7. Configuration

| Setting | Value | How to change |
|---|---|---|
| `worker_mode` | `"full"` to enable MIDI | `WORKER_MODE=full` env var; restart required |
| Poll interval | 2,000 ms | Edit `@poll_interval_ms` in `device_manager.ex`, redeploy |
| DeviceResearch | No runtime config | Vendor table is compiled in |

---

## 8. Restart Procedure

```elixir
# Restart DeviceManager (supervisor will auto-restart)
pid = Process.whereis(SoundForge.MIDI.DeviceManager)
Process.exit(pid, :kill)
# Wait 4–6 seconds for nif_ever_succeeded to become true again

# Restart DeviceResearch (clears ETS cache)
pid = Process.whereis(SoundForge.MIDI.DeviceResearch)
Process.exit(pid, :kill)

# Full MIDI subsystem restart
for name <- [SoundForge.MIDI.DeviceManager, SoundForge.MIDI.DeviceResearch] do
  pid = Process.whereis(name)
  if pid, do: Process.exit(pid, :kill)
end
```

---

## 9. Quick Diagnostic Checklist

```
[ ] Process.whereis(SoundForge.MIDI.DeviceManager)  — not nil?
[ ] Application.get_env(:sound_forge, :worker_mode) — "full"?
[ ] :ets.lookup(:midi_devices, :devices)             — table exists?
[ ] Midiex.devices()                                  — NIF returns list?
[ ] nif_ever_succeeded                                — true?
[ ] Process.whereis(SoundForge.PubSub)               — alive?
[ ] /usr/sbin/ioreg -l -w 0                           — exits 0?
```
