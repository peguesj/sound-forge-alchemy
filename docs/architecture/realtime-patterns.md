---
title: Real-Time Patterns
parent: Architecture
nav_order: 8
---

[Home](../index.md) > [Architecture](index.md) > Real-Time Patterns

# Real-Time Patterns

WebSocket optimization, JS.dispatch architecture, and client-server event flow for latency-sensitive audio interactions.

## Table of Contents

- [JS.dispatch + JS.push Architecture](#jsdispatch--jspush-architecture)
- [WebSocket Optimization](#websocket-optimization)
- [BPM Throttle](#bpm-throttle)
- [PubSub Event Flow](#pubsub-event-flow)

---

## JS.dispatch + JS.push Architecture

Latency-sensitive DJ interactions (play, pause, cue trigger, hot cue) use a dual-path event model that separates the client-side action from the server-side state update.

### Problem

Standard Phoenix LiveView events (`phx-click`) require a WebSocket round-trip before the client sees a response. For audio playback, even 20-50ms of latency produces an audible delay between button press and sound.

### Solution

Each interaction fires two events simultaneously:

1. **`JS.dispatch`** -- emits a DOM `CustomEvent` caught by the JS hook on the same frame. The Web Audio API acts immediately (start/stop playback, trigger cue, adjust gain).
2. **`JS.push`** -- sends the event to the LiveView process for state persistence, session updates, and broadcasting to other clients.

```elixir
<button phx-click={
  JS.dispatch("dj:toggle-play", to: "#deck-#{@deck}")
  |> JS.push("toggle_play", value: %{deck: @deck})
}>
```

```javascript
// In the DjDeck hook
this.el.addEventListener("dj:toggle-play", (e) => {
  // Fires immediately -- no network round-trip
  if (this.playing) {
    this.source.stop();
  } else {
    this.source.start();
  }
});
```

### Server-Side Guard

The server handler updates assigns and persists the deck session but does **not** push a playback command back to the originating client. This prevents double-triggering:

```elixir
def handle_event("toggle_play", %{"deck" => deck}, socket) do
  # Update server state only -- no push_event back to the caller
  {:noreply, update_deck_state(socket, deck, :toggle_play)}
end
```

Other connected clients (e.g., a second browser tab or a spectator view) receive the state change via PubSub broadcast.

### Applicable Events

| Event | JS.dispatch target | Server handler |
|-------|--------------------|----------------|
| Play/Pause | `dj:toggle-play` | `toggle_play` |
| Hot Cue Set | `dj:set-hot-cue` | `set_hot_cue` |
| Cue Trigger | `dj:trigger-cue` | `trigger_cue` |
| Loop Toggle | `dj:toggle-loop` | `toggle_loop` |
| Crossfader Move | `dj:crossfader` | `update_crossfader` |

---

## WebSocket Optimization

### Debug Log Guard

**Problem:** The `debug_log` event handler was firing on every LiveView event during playback, sending debug payloads to the client at ~30Hz. This flooded the WebSocket with unnecessary traffic.

**Fix:** Added a guard clause that only pushes debug logs when the debug panel is open:

```elixir
def handle_event("debug_log", params, socket) do
  if socket.assigns[:debug_panel_open] do
    {:noreply, push_event(socket, "debug_update", params)}
  else
    {:noreply, socket}
  end
end
```

This reduced idle WebSocket traffic from ~30 messages/second to near zero during normal playback.

### Event Coalescing

Rapid-fire UI events (crossfader drag, EQ knob turn) are coalesced on the client side using `requestAnimationFrame` debouncing. Only the latest value per animation frame is sent to the server:

```javascript
// In the DjDeck hook
handleCrossfaderInput(value) {
  this.pendingCrossfader = value;
  if (!this.rafPending) {
    this.rafPending = true;
    requestAnimationFrame(() => {
      this.pushEvent("update_crossfader", { value: this.pendingCrossfader });
      this.rafPending = false;
    });
  }
}
```

---

## BPM Throttle

BPM slider adjustments generate continuous values as the user drags. Sending each intermediate value to the server wastes bandwidth and triggers unnecessary re-renders.

### Implementation

The `update_bpm` handler enforces a 5-second throttle interval on server-side processing:

```elixir
@bpm_throttle_ms 5_000

def handle_event("update_bpm", %{"bpm" => bpm, "deck" => deck}, socket) do
  now = System.monotonic_time(:millisecond)
  last = socket.assigns[:last_bpm_update] || 0

  if now - last >= @bpm_throttle_ms do
    socket =
      socket
      |> assign(:last_bpm_update, now)
      |> update_deck_bpm(deck, bpm)

    {:noreply, socket}
  else
    {:noreply, socket}
  end
end
```

The actual BPM change is applied locally via `JS.dispatch` on every slider movement, so the user hears the tempo change immediately. The throttled server update persists the final value and syncs other clients.

---

## PubSub Event Flow

Real-time updates between the server and multiple connected clients use Phoenix PubSub. The DJ system subscribes to deck-specific topics:

```
Topic: "dj:session:#{user_id}"
Events:
  - {:deck_state_changed, deck_id, new_state}
  - {:track_loaded, deck_id, track_id}
  - {:cue_updated, deck_id, cue_point}
```

### LiveComponent Forwarding

Because DJ and DAW are LiveComponents (not standalone LiveViews), PubSub messages arrive at the parent `DashboardLive` process. The parent forwards relevant messages to the child component via `send_update/3`:

```elixir
# In DashboardLive
def handle_info({:deck_state_changed, deck, state}, socket) do
  send_update(SoundForgeWeb.DjLive, id: "dj", deck: deck, state: state)
  {:noreply, socket}
end
```

---

## See Also

- [DJ / DAW Tools](../features/dj-daw.md)
- [Integration Patterns](07_INTEGRATION_PATTERNS.md)
- [Stack Details](stack.md)

---

[← Integration Patterns](07_INTEGRATION_PATTERNS.md) | [Next: Stack Details →](stack.md)
