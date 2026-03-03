/**
 * DjDeck Hook - Dual-deck DJ audio engine with WaveSurfer waveforms and crossfader.
 *
 * Manages TWO independent AudioContexts (one per deck), each with their own
 * GainNode for volume. WaveSurfer instances provide visual-only waveform
 * rendering. A crossfader adjusts the gain balance between the two decks.
 * Loop playback engine with beat quantization and waveform region display.
 */
import WaveSurfer from "wavesurfer.js"
import RegionsPlugin from "wavesurfer.js/dist/plugins/regions.esm.js"
import TimelinePlugin from "wavesurfer.js/dist/plugins/timeline.esm.js"
import MinimapPlugin from "wavesurfer.js/dist/plugins/minimap.esm.js"

// Module-level decoded AudioBuffer cache keyed by URL.
// Survives LiveView reconnects (hook destroy/remount cycles) so re-loading
// the same track skips the fetch + decodeAudioData round-trip entirely.
const _audioBufferCache = new Map()

const DjDeck = {
  mounted() {
    console.log("[DjDeck] Hook mounted")

    // Deck audio state: keyed by deck number (1-4)
    // Decks 3/4 are loop-track decks with simplified playback
    const deckTemplate = () => ({
      audioContext: null, masterGain: null, eqLow: null, eqMid: null, eqHigh: null,
      deckFilter: null, stems: {}, wavesurfer: null, regionsPlugin: null, loopRegion: null,
      cueMarkers: [], isPlaying: false, startTime: 0, pauseOffset: 0, duration: 0,
      loop: null, pitch: 0.0, tempo: null, beatTimes: [], beatMarkers: [],
      timeFactor: 1.0,
      stemStates: {},
      metronomeOscillator: null, metronomePlaying: false
    })
    this.decks = { 1: deckTemplate(), 2: deckTemplate(), 3: deckTemplate(), 4: deckTemplate() }

    // Unlock all AudioContexts on first user interaction (browser autoplay policy).
    // AudioContexts created outside a user gesture start suspended; this listener
    // resumes them as soon as the user clicks or taps anywhere on the page.
    this._unlockAudio = () => {
      Object.values(this.decks).forEach(deck => {
        if (deck.audioContext && deck.audioContext.state === "suspended") {
          deck.audioContext.resume().catch(() => {})
        }
      })
    }
    document.addEventListener("click", this._unlockAudio, { passive: true })
    document.addEventListener("touchstart", this._unlockAudio, { passive: true })

    this.crossfaderValue = 0 // -100 (deck1) to +100 (deck2), 0 = center
    this.crossfaderCurve = "linear" // "linear" | "equal_power" | "sharp"
    this.deckVolumes = { 1: 1.0, 2: 1.0 } // per-deck volume (0.0 - 1.0)

    // Server -> Client events
    this.handleEvent("load_deck_audio", (payload) => this._loadDeckAudio(payload))
    this.handleEvent("play_deck", (payload) => this._playDeck(payload))
    this.handleEvent("set_crossfader", (payload) => this._setCrossfader(payload))
    this.handleEvent("set_crossfader_curve", (payload) => this._setCrossfaderCurve(payload))
    this.handleEvent("set_deck_volume", (payload) => this._setDeckVolume(payload))
    this.handleEvent("set_loop", (payload) => this._setLoop(payload))
    this.handleEvent("set_cue_points", (payload) => this._setCuePoints(payload))
    this.handleEvent("seek_and_play", (payload) => this._seekAndPlay(payload))
    this.handleEvent("seek_deck", (payload) => this._handleSeekDeck(payload))
    this.handleEvent("set_time_factor", (payload) => this._setTimeFactor(payload))
    this.handleEvent("set_eq_kill", (payload) => this._setEqKill(payload))
    this.handleEvent("set_stem_states", (payload) => this._setStemStates(payload))
    this.handleEvent("toggle_metronome", (payload) => this._toggleMetronome(payload))
    this.handleEvent("set_filter", (payload) => this._setFilter(payload))
    this.handleEvent("set_pitch", (payload) => this._setPitch(payload))
    this.handleEvent("stem_loop_preview", (payload) => this._stemLoopPreview(payload))

    // Instant client-side audio actions — fired via JS.dispatch() before the
    // server round-trip completes. Eliminates the phx-click → server → push_event
    // latency for play/pause and hot cue seeks.
    this._onDjPlay = (e) => this._playDeck({ deck: e.detail.deck, playing: e.detail.playing })
    this._onDjSeek = (e) => this._seekAndPlay({ deck: e.detail.deck, position: e.detail.position })
    this.el.addEventListener("dj:play", this._onDjPlay)
    this.el.addEventListener("dj:seek", this._onDjSeek)
  },

  /**
   * Load audio stems into a deck's AudioContext and render WaveSurfer waveform.
   * @param {Object} payload - { deck: number, urls: [{type, url}], track_title: string }
   */
  async _loadDeckAudio({ deck, urls, track_title, tempo, beat_times }) {
    console.log(`[DjDeck] Loading deck ${deck} with ${urls.length} sources`, urls)

    const deckState = this.decks[deck]
    if (!deckState) return

    // Cleanup previous audio for this deck
    this._cleanupDeck(deck)

    // Store analysis data for beat grid
    deckState.tempo = tempo || null
    deckState.beatTimes = beat_times || []
    deckState._audioReady = false
    deckState._pendingPlay = false

    if (!urls || urls.length === 0) {
      console.warn(`[DjDeck] No audio URLs for deck ${deck}`)
      return
    }

    try {
      // Create a fresh AudioContext for this deck
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const masterGain = ctx.createGain()
      masterGain.gain.value = 1.0

      // EQ chain: Low shelf → Mid peak → High shelf → LP/HP filter → master
      const eqLow = ctx.createBiquadFilter()
      eqLow.type = "lowshelf"; eqLow.frequency.value = 200; eqLow.gain.value = 0

      const eqMid = ctx.createBiquadFilter()
      eqMid.type = "peaking"; eqMid.frequency.value = 1000; eqMid.Q.value = 1.0; eqMid.gain.value = 0

      const eqHigh = ctx.createBiquadFilter()
      eqHigh.type = "highshelf"; eqHigh.frequency.value = 8000; eqHigh.gain.value = 0

      const deckFilter = ctx.createBiquadFilter()
      deckFilter.type = "allpass"  // neutral until set_filter event

      // Chain: stemGainNodes → eqLow → eqMid → eqHigh → deckFilter → masterGain → destination
      eqLow.connect(eqMid)
      eqMid.connect(eqHigh)
      eqHigh.connect(deckFilter)
      deckFilter.connect(masterGain)
      masterGain.connect(ctx.destination)

      deckState.audioContext = ctx
      deckState.masterGain = masterGain
      deckState.eqLow = eqLow
      deckState.eqMid = eqMid
      deckState.eqHigh = eqHigh
      deckState.deckFilter = deckFilter
      deckState.stems = {}

      // Start WaveSurfer waveform IMMEDIATELY — visual-only, fetches its own stream.
      // This makes the waveform visible while audio buffers decode in the background.
      this._initWaveform(deck, urls)

      // Load all audio sources in parallel, using the module-level decoded
      // buffer cache to skip fetch+decode for previously-loaded URLs.
      const loadPromises = urls.map(async (item) => {
        try {
          let audioBuffer = _audioBufferCache.get(item.url)

          if (!audioBuffer) {
            const response = await fetch(item.url)
            if (!response.ok) {
              console.error(`[DjDeck] Deck ${deck}: HTTP ${response.status} for ${item.url}`)
              return
            }
            const arrayBuffer = await response.arrayBuffer()
            audioBuffer = await ctx.decodeAudioData(arrayBuffer)
            _audioBufferCache.set(item.url, audioBuffer)
          }

          const gainNode = ctx.createGain()
          gainNode.connect(deckState.eqLow)  // into EQ chain, not directly to masterGain

          deckState.stems[item.type] = {
            buffer: audioBuffer,
            gainNode: gainNode,
            source: null
          }
        } catch (err) {
          console.error(`[DjDeck] Deck ${deck}: failed to load ${item.type}:`, err)
        }
      })

      // Decode in background — do not await here so waveform renders instantly.
      Promise.all(loadPromises).then(() => {
        const durations = Object.values(deckState.stems).map(s => s.buffer.duration)
        deckState.duration = Math.max(...durations, 0)
        deckState._audioReady = true
        console.log(`[DjDeck] Deck ${deck}: loaded ${Object.keys(deckState.stems).length} sources, duration=${deckState.duration.toFixed(1)}s`)

        this._applyCrossfader()

        // If play was requested while audio was still decoding, start now.
        if (deckState._pendingPlay) {
          deckState._pendingPlay = false
          if (deckState.audioContext.state === "suspended") {
            deckState.audioContext.resume().catch(() => {}).then(() => this._startDeck(deck))
          } else {
            this._startDeck(deck)
          }
        }
      }).catch(err => {
        deckState._audioReady = false
        console.error(`[DjDeck] Deck ${deck}: audio decode failed:`, err)
      })

    } catch (err) {
      console.error(`[DjDeck] Deck ${deck}: AudioContext init failed:`, err)
    }
  },

  /**
   * Create or recreate the WaveSurfer waveform for a deck.
   */
  _initWaveform(deck, urls) {
    const deckState = this.decks[deck]
    const container = document.getElementById(`waveform-deck-${deck}`)
    if (!container) {
      console.warn(`[DjDeck] Waveform container not found for deck ${deck}`)
      return
    }

    // Destroy previous WaveSurfer instance
    if (deckState.wavesurfer) {
      deckState.wavesurfer.destroy()
      deckState.wavesurfer = null
      deckState.regionsPlugin = null
      deckState.loopRegion = null
    }

    // Prefer vocals stem for waveform, else first available
    const vocalsUrl = urls.find(u => u.type === "vocals")?.url
    const waveformUrl = vocalsUrl || urls[0]?.url
    if (!waveformUrl) return

    const waveColor = deck === 1 ? "#22d3ee" : "#fb923c"     // cyan / orange
    const progressColor = deck === 1 ? "#06b6d4" : "#f97316"

    // Create regions plugin for loop visualization
    const regions = RegionsPlugin.create()
    deckState.regionsPlugin = regions

    // Create minimap plugin for full-track overview
    const minimap = MinimapPlugin.create({
      height: 20,
      waveColor: deck === 1 ? "#164e63" : "#431407",
      progressColor: deck === 1 ? "#0891b2" : "#ea580c",
      insertPosition: "beforebegin"
    })

    // Build plugins array
    const plugins = [regions, minimap]

    // Add timeline plugin if we have tempo data for beat grid markers
    if (deckState.tempo && deckState.tempo > 0) {
      const beatInterval = 60.0 / deckState.tempo
      const timeline = TimelinePlugin.create({
        timeInterval: beatInterval,
        primaryLabelInterval: 4,
        style: {
          fontSize: "9px",
          color: "#6b7280"
        },
        formatTimeCallback: (seconds) => {
          if (deckState.tempo <= 0) return ""
          const beatNum = Math.floor(seconds / beatInterval) + 1
          const barNum = Math.ceil(beatNum / 4)
          const beatInBar = ((beatNum - 1) % 4) + 1
          return beatInBar === 1 ? `${barNum}` : ""
        }
      })
      plugins.push(timeline)
    }

    const ws = WaveSurfer.create({
      container: container,
      waveColor: waveColor,
      progressColor: progressColor,
      cursorColor: "#a855f7",
      height: 80,
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      interact: true,
      url: waveformUrl,
      normalize: true,
      minPxPerSec: 50,
      autoScroll: true,
      autoCenter: true,
      plugins: plugins
    })

    ws.on("ready", () => {
      console.log(`[DjDeck] Deck ${deck}: waveform ready`)
      ws.setMuted(true) // visual only

      // Render beat grid from analysis data
      if (deckState.beatTimes && deckState.beatTimes.length > 0) {
        this._renderBeatGrid(deck)
      }

      // If loop was already set before waveform was ready, render it now
      if (deckState.loop && deckState.loop.loop_end_ms) {
        this._renderLoopRegion(deck)
      }

      // If cue points were set before waveform was ready, render them now
      if (deckState._pendingCuePoints) {
        this._setCuePoints({ deck, cue_points: deckState._pendingCuePoints })
        deckState._pendingCuePoints = null
      }
    })

    ws.on("error", (error) => {
      console.error(`[DjDeck] Deck ${deck}: waveform error:`, error)
    })

    // Click-to-seek on waveform
    ws.on("interaction", (newTime) => {
      this._seekDeck(deck, newTime)
      this.pushEvent("time_update", { deck: deck, position: newTime })
    })

    deckState.wavesurfer = ws
  },

  /**
   * Handle play/pause for a deck.
   * @param {Object} payload - { deck: number, playing: boolean }
   */
  async _playDeck({ deck, playing }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    // If audio buffers are still decoding, queue the play request.
    // _loadDeckAudio will call _startDeck when decode completes.
    if (playing && !deckState._audioReady) {
      console.log(`[DjDeck] Deck ${deck}: play queued — audio still loading`)
      deckState._pendingPlay = true
      return
    }

    if (!playing) {
      deckState._pendingPlay = false
    }

    // Await resume so the context is truly running before source nodes are started.
    // AudioContexts created outside a user gesture start in "suspended" state.
    if (deckState.audioContext.state === "suspended") {
      try {
        await deckState.audioContext.resume()
      } catch (err) {
        console.warn(`[DjDeck] Deck ${deck}: AudioContext.resume() failed:`, err)
      }
    }

    if (playing) {
      this._startDeck(deck)
    } else {
      this._pauseDeck(deck)
    }
  },

  _startDeck(deck) {
    const deckState = this.decks[deck]
    if (deckState.isPlaying) return

    // Create new source nodes
    Object.entries(deckState.stems).forEach(([type, stem]) => {
      const source = deckState.audioContext.createBufferSource()
      source.buffer = stem.buffer
      source.connect(stem.gainNode)
      source.start(0, deckState.pauseOffset)
      stem.source = source
    })

    // Apply stored pitch + time factor to all newly created source nodes
    const timeFactor = deckState.timeFactor || 1.0
    const rate = timeFactor * (1.0 + (deckState.pitch / 100.0))
    if (rate !== 1.0) {
      Object.values(deckState.stems).forEach(stem => {
        if (stem.source) {
          stem.source.playbackRate.setValueAtTime(rate, deckState.audioContext.currentTime)
        }
      })
    }

    deckState.startTime = deckState.audioContext.currentTime - deckState.pauseOffset
    deckState.isPlaying = true

    // Start time update interval for this deck
    this._startTimeUpdate(deck)
  },

  _pauseDeck(deck) {
    const deckState = this.decks[deck]
    if (!deckState.isPlaying) return

    deckState.pauseOffset = deckState.audioContext.currentTime - deckState.startTime

    Object.values(deckState.stems).forEach(stem => {
      if (stem.source) {
        try { stem.source.stop() } catch (_e) { /* already stopped */ }
        stem.source = null
      }
    })

    deckState.isPlaying = false
    this._stopTimeUpdate(deck)
  },

  _seekDeck(deck, time) {
    const deckState = this.decks[deck]
    if (!deckState.audioContext) return

    const wasPlaying = deckState.isPlaying
    if (wasPlaying) this._pauseDeck(deck)
    deckState.pauseOffset = time
    if (wasPlaying) this._startDeck(deck)

    // Sync waveform cursor
    if (deckState.wavesurfer && deckState.duration > 0) {
      deckState.wavesurfer.seekTo(time / deckState.duration)
    }
  },

  _startTimeUpdate(deck) {
    const deckState = this.decks[deck]
    // Clear any existing interval
    this._stopTimeUpdate(deck)

    deckState._timeInterval = setInterval(() => {
      if (deckState.isPlaying && deckState.audioContext) {
        const currentTime = deckState.audioContext.currentTime - deckState.startTime
        const currentTimeMs = currentTime * 1000

        // Check loop boundary: if loop is active and we've reached loop_end, jump to loop_start
        if (deckState.loop && deckState.loop.active && deckState.loop.loop_end_ms) {
          if (currentTimeMs >= deckState.loop.loop_end_ms) {
            const loopStartSec = deckState.loop.loop_start_ms / 1000
            console.log(`[DjDeck] Deck ${deck}: loop jump to ${loopStartSec.toFixed(2)}s`)
            this._seekDeck(deck, loopStartSec)
            return // skip the rest of this tick; next tick will report from loop start
          }
        }

        if (currentTime >= deckState.duration) {
          // Track ended
          this._pauseDeck(deck)
          deckState.pauseOffset = 0
          this.pushEvent("deck_stopped", { deck: deck })
          if (deckState.wavesurfer) deckState.wavesurfer.seekTo(0)
          // Update transport bridge
          window.__djTransport = { currentTime: 0, duration: deckState.duration, playing: false, deck }
        } else {
          this.pushEvent("time_update", { deck: deck, position: currentTime })
          // Sync waveform cursor
          if (deckState.wavesurfer && deckState.duration > 0) {
            deckState.wavesurfer.seekTo(currentTime / deckState.duration)
          }
          // Update transport bridge for TransportBar
          window.__djTransport = { currentTime, duration: deckState.duration, playing: true, deck }
        }
      }
    }, 50) // 50ms for tighter loop accuracy (was 250ms)
  },

  _stopTimeUpdate(deck) {
    const deckState = this.decks[deck]
    if (deckState._timeInterval) {
      clearInterval(deckState._timeInterval)
      deckState._timeInterval = null
    }
  },

  // -- Loop Playback Engine --

  /**
   * Handle set_loop event from server.
   * @param {Object} payload - { deck, loop_start_ms, loop_end_ms, active }
   */
  _setLoop({ deck, loop_start_ms, loop_end_ms, active }) {
    const deckState = this.decks[deck]
    if (!deckState) return

    console.log(`[DjDeck] Deck ${deck}: set_loop start=${loop_start_ms}ms end=${loop_end_ms}ms active=${active}`)

    deckState.loop = {
      loop_start_ms: loop_start_ms,
      loop_end_ms: loop_end_ms,
      active: active
    }

    // Render or clear loop region on waveform
    if (loop_start_ms != null && loop_end_ms != null) {
      this._renderLoopRegion(deck)
    } else {
      this._clearLoopRegion(deck)
    }
  },

  /**
   * Render the loop region as a highlighted overlay on the WaveSurfer waveform.
   */
  _renderLoopRegion(deck) {
    const deckState = this.decks[deck]
    if (!deckState.wavesurfer || !deckState.regionsPlugin || !deckState.loop) return
    if (deckState.duration <= 0) return

    // Clear existing loop region
    this._clearLoopRegion(deck)

    const loop = deckState.loop
    if (loop.loop_start_ms == null || loop.loop_end_ms == null) return

    const startSec = loop.loop_start_ms / 1000
    const endSec = loop.loop_end_ms / 1000

    // Color based on deck and active state
    const activeColor = deck === 1 ? "rgba(34, 211, 238, 0.25)" : "rgba(251, 146, 60, 0.25)"
    const inactiveColor = "rgba(156, 163, 175, 0.15)"
    const color = loop.active ? activeColor : inactiveColor

    try {
      deckState.loopRegion = deckState.regionsPlugin.addRegion({
        start: startSec,
        end: endSec,
        color: color,
        drag: false,
        resize: false
      })
    } catch (err) {
      console.error(`[DjDeck] Deck ${deck}: failed to render loop region:`, err)
    }
  },

  /**
   * Remove the loop region from the waveform.
   */
  _clearLoopRegion(deck) {
    const deckState = this.decks[deck]
    if (deckState.loopRegion) {
      try {
        deckState.loopRegion.remove()
      } catch (_e) { /* already removed */ }
      deckState.loopRegion = null
    }
  },

  // -- Cue Point Markers --

  /**
   * Display cue point markers on the WaveSurfer waveform.
   * @param {Object} payload - { deck: number, cue_points: [{id, position_ms, label, color, cue_type}] }
   */
  _setCuePoints({ deck, cue_points }) {
    const deckState = this.decks[deck]
    if (!deckState) return

    console.log(`[DjDeck] Deck ${deck}: setting ${cue_points.length} cue point markers`)

    // Clear existing cue markers
    this._clearCueMarkers(deck)

    if (!deckState.regionsPlugin || !deckState.wavesurfer || deckState.duration <= 0) {
      // Store cue points so they can be rendered once waveform is ready
      deckState._pendingCuePoints = cue_points
      return
    }

    cue_points.forEach((cp) => {
      try {
        const positionSec = cp.position_ms / 1000
        const marker = deckState.regionsPlugin.addRegion({
          start: positionSec,
          end: positionSec,
          color: cp.color || "#ffffff",
          content: cp.label || "",
          drag: false,
          resize: false
        })
        deckState.cueMarkers.push(marker)
      } catch (err) {
        console.error(`[DjDeck] Deck ${deck}: failed to add cue marker:`, err)
      }
    })
  },

  /**
   * Clear all cue point markers from a deck's waveform.
   */
  _clearCueMarkers(deck) {
    const deckState = this.decks[deck]
    if (!deckState) return

    deckState.cueMarkers.forEach((marker) => {
      try { marker.remove() } catch (_e) { /* already removed */ }
    })
    deckState.cueMarkers = []
  },

  /**
   * Seek to a position and start playing.
   * @param {Object} payload - { deck: number, position: number (seconds) }
   */
  async _seekAndPlay({ deck, position }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    console.log(`[DjDeck] Deck ${deck}: seek_and_play to ${position.toFixed(2)}s`)

    // If audio not yet ready, queue the seek position and trigger play after decode.
    if (!deckState._audioReady) {
      deckState.pauseOffset = position
      deckState._pendingPlay = true
      return
    }

    // Resume AudioContext if suspended (browser autoplay policy)
    if (deckState.audioContext.state === "suspended") {
      try {
        await deckState.audioContext.resume()
      } catch (err) {
        console.warn(`[DjDeck] Deck ${deck}: AudioContext.resume() failed in seek_and_play:`, err)
      }
    }

    // Seek to position
    this._seekDeck(deck, position)

    // Start playback if not already playing
    if (!deckState.isPlaying) {
      this._startDeck(deck)
    }
  },

  /**
   * Seek to a position WITHOUT starting playback (loop arm, cue set, etc.).
   * @param {Object} payload - { deck: number, position: number (seconds) }
   */
  _handleSeekDeck({ deck, position }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    console.log(`[DjDeck] Deck ${deck}: seek_deck (no-play) to ${position.toFixed(2)}s`)

    if (!deckState._audioReady) {
      // Store position for when audio is ready; do NOT arm pending play
      deckState.pauseOffset = position
      return
    }

    this._seekDeck(deck, position)
  },

  // -- Time Factor (Double / Half Time) --

  /**
   * Set the time factor for a deck (1.0 = normal, 2.0 = double time, 0.5 = half time).
   * Combines with pitch so double time increases both speed and pitch.
   * @param {Object} payload - { deck, factor }
   */
  _setTimeFactor({ deck, factor }) {
    const deckState = this.decks[deck]
    if (!deckState) return
    deckState.timeFactor = factor
    const combinedRate = factor * (1.0 + (deckState.pitch / 100.0))
    Object.values(deckState.stems).forEach(stem => {
      if (stem.source) {
        stem.source.playbackRate.setValueAtTime(combinedRate, deckState.audioContext.currentTime)
      }
    })
    console.log(`[DjDeck] Deck ${deck}: time_factor=${factor} combinedRate=${combinedRate.toFixed(3)}`)
  },

  // -- EQ Kill Switches --

  /**
   * Kill or restore an EQ band for a deck.
   * @param {Object} payload - { deck, band: "low"|"mid"|"high", active: bool }
   */
  _setEqKill({ deck, band, active }) {
    const deckState = this.decks[deck]
    if (!deckState) return
    const KILL_GAIN = -40  // dB — effectively silent
    const node = band === "low" ? deckState.eqLow : band === "mid" ? deckState.eqMid : deckState.eqHigh
    if (!node) return
    node.gain.setValueAtTime(active ? KILL_GAIN : 0, deckState.audioContext.currentTime)
    console.log(`[DjDeck] Deck ${deck}: EQ ${band} kill=${active}`)
  },

  // -- Stem Solo / Mute --

  /**
   * Set mute/solo/on states for all stems of a deck.
   * @param {Object} payload - { deck, stem_states: { "vocals": "on"|"mute"|"solo", ... } }
   */
  _setStemStates({ deck, stem_states }) {
    const deckState = this.decks[deck]
    if (!deckState) return
    deckState.stemStates = stem_states

    const hasSolo = Object.values(stem_states).some(v => v === "solo")

    Object.entries(deckState.stems).forEach(([type, stem]) => {
      const state = stem_states[type] || "on"
      let gain = 1.0
      if (state === "mute") gain = 0.0
      else if (hasSolo) gain = (state === "solo") ? 1.0 : 0.0
      stem.gainNode.gain.setValueAtTime(gain, deckState.audioContext ? deckState.audioContext.currentTime : 0)
    })
    console.log(`[DjDeck] Deck ${deck}: stem states`, stem_states)
  },

  // -- LP/HP Filter --

  /**
   * Set the deck-wide filter (lowpass, highpass, or bypass).
   * @param {Object} payload - { deck, mode: "none"|"lp"|"hp", cutoff: 0.0-1.0 }
   */
  _setFilter({ deck, mode, cutoff }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.deckFilter) return

    // Map 0.0-1.0 to 20Hz-20000Hz on a logarithmic scale
    const minFreq = 20, maxFreq = 20000
    const freq = minFreq * Math.pow(maxFreq / minFreq, cutoff)

    if (mode === "lp") {
      deckState.deckFilter.type = "lowpass"
      deckState.deckFilter.frequency.setValueAtTime(freq, deckState.audioContext.currentTime)
      deckState.deckFilter.Q.value = 0.7
    } else if (mode === "hp") {
      deckState.deckFilter.type = "highpass"
      deckState.deckFilter.frequency.setValueAtTime(freq, deckState.audioContext.currentTime)
      deckState.deckFilter.Q.value = 0.7
    } else {
      deckState.deckFilter.type = "allpass"  // bypass
    }
    console.log(`[DjDeck] Deck ${deck}: filter mode=${mode} freq=${freq.toFixed(0)}Hz`)
  },

  // -- Metronome --

  /**
   * Start or stop the global metronome click track.
   * Uses a shared AudioContext on deck 1 as the clock source.
   * @param {Object} payload - { active: bool, bpm: number, volume: 0.0-1.0 }
   */
  _toggleMetronome({ active, bpm, volume }) {
    if (this._metronomeInterval) {
      clearInterval(this._metronomeInterval)
      this._metronomeInterval = null
    }
    if (!active) {
      console.log("[DjDeck] Metronome stopped")
      return
    }

    const beatMs = 60000 / (bpm || 120)
    console.log(`[DjDeck] Metronome started: ${bpm}BPM, vol=${volume}`)

    const click = () => {
      // Use deck 1's AudioContext if available, else skip
      const ctx = this.decks[1]?.audioContext || this.decks[2]?.audioContext
      if (!ctx || ctx.state === "closed") return
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.frequency.value = 880  // A5 — crisp click tone
      gain.gain.setValueAtTime(volume || 0.3, ctx.currentTime)
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.05)
      osc.start(ctx.currentTime)
      osc.stop(ctx.currentTime + 0.05)
    }

    click()  // immediate first click
    this._metronomeInterval = setInterval(click, beatMs)
  },

  // -- Pitch / Tempo Engine --

  /**
   * Handle set_pitch event from server.
   * Adjusts AudioBufferSourceNode.playbackRate for all active stems on a deck.
   * @param {Object} payload - { deck: number, value: number (-8.0 to 8.0) }
   */
  _setPitch({ deck, value }) {
    const deckState = this.decks[deck]
    if (!deckState) return

    console.log(`[DjDeck] Deck ${deck}: set_pitch ${value}%`)
    deckState.pitch = value
    const rate = 1.0 + (value / 100.0)

    // If deck is currently playing, update all active source nodes immediately
    if (deckState.isPlaying && deckState.audioContext) {
      Object.values(deckState.stems).forEach(stem => {
        if (stem.source) {
          stem.source.playbackRate.setValueAtTime(rate, deckState.audioContext.currentTime)
        }
      })
    }
    // If not playing, the rate will be applied when _startDeck creates new sources
  },

  /**
   * Apply crossfader value to both decks' master gains.
   * value: -100 = deck 1 full / deck 2 silent
   *           0 = both full
   *        +100 = deck 1 silent / deck 2 full
   */
  _setCrossfader({ value }) {
    this.crossfaderValue = value
    this._applyCrossfader()
  },

  /**
   * Switch crossfader curve algorithm.
   * @param {Object} payload - { curve: "linear" | "equal_power" | "sharp" }
   */
  _setCrossfaderCurve({ curve }) {
    console.log(`[DjDeck] Crossfader curve set to: ${curve}`)
    this.crossfaderCurve = curve
    this._applyCrossfader()
  },

  /**
   * Set per-deck volume independently from crossfader.
   * @param {Object} payload - { deck: number, level: number (0-100) }
   */
  _setDeckVolume({ deck, level }) {
    console.log(`[DjDeck] Deck ${deck} volume set to: ${level}%`)
    this.deckVolumes[deck] = level / 100.0
    this._applyCrossfader()
  },

  /**
   * Calculate crossfader gains based on the selected curve, then multiply
   * by per-deck volume and apply to master gain nodes.
   */
  _applyCrossfader() {
    const value = this.crossfaderValue
    const deck1 = this.decks[1]
    const deck2 = this.decks[2]

    let cfGain1 = 1.0
    let cfGain2 = 1.0

    switch (this.crossfaderCurve) {
      case "equal_power": {
        // Normalize crossfader value to 0.0 (full deck 1) -> 1.0 (full deck 2)
        const cfNorm = (value + 100) / 200.0
        cfGain1 = Math.cos(cfNorm * Math.PI / 2)
        cfGain2 = Math.sin(cfNorm * Math.PI / 2)
        break
      }

      case "sharp": {
        // Hard cut at edges: deck1 full when cf < -80, zero when cf > 80, linear between
        if (value <= -80) {
          cfGain1 = 1.0
          cfGain2 = 0.0
        } else if (value >= 80) {
          cfGain1 = 0.0
          cfGain2 = 1.0
        } else {
          // Linear transition between -80 and +80
          const norm = (value + 80) / 160.0
          cfGain1 = 1.0 - norm
          cfGain2 = norm
        }
        break
      }

      case "linear":
      default: {
        // Original behavior: center = both full, edges = one silent
        if (value > 0) {
          cfGain1 = 1.0 - (value / 100)
        } else if (value < 0) {
          cfGain2 = 1.0 - (Math.abs(value) / 100)
        }
        break
      }
    }

    // Multiply crossfader gain by per-deck volume
    const finalGain1 = cfGain1 * this.deckVolumes[1]
    const finalGain2 = cfGain2 * this.deckVolumes[2]

    if (deck1.masterGain && deck1.audioContext) {
      deck1.masterGain.gain.setValueAtTime(finalGain1, deck1.audioContext.currentTime)
    }
    if (deck2.masterGain && deck2.audioContext) {
      deck2.masterGain.gain.setValueAtTime(finalGain2, deck2.audioContext.currentTime)
    }
  },

  /**
   * Render beat grid markers from analysis beat_times data.
   * Downbeats (every 4th beat) are highlighted with stronger color.
   */
  _renderBeatGrid(deck) {
    const deckState = this.decks[deck]
    if (!deckState.regionsPlugin || !deckState.beatTimes) return

    const beatColor = deck === 1 ? "rgba(34, 211, 238, 0.12)" : "rgba(251, 146, 60, 0.12)"
    const downbeatColor = deck === 1 ? "rgba(34, 211, 238, 0.25)" : "rgba(251, 146, 60, 0.25)"

    deckState.beatMarkers = deckState.beatMarkers || []

    deckState.beatTimes.forEach((time, index) => {
      const isDownbeat = index % 4 === 0
      try {
        const marker = deckState.regionsPlugin.addRegion({
          start: time,
          end: time + 0.01,
          color: isDownbeat ? downbeatColor : beatColor,
          drag: false,
          resize: false
        })
        deckState.beatMarkers.push(marker)
      } catch (_e) { /* skip failed markers */ }
    })

    console.log(`[DjDeck] Deck ${deck}: rendered ${deckState.beatMarkers.length} beat grid markers`)
  },

  /**
   * Play a short audio preview of a stem loop region.
   * Fetches the stem audio, decodes it, and plays only the specified region.
   * Auto-stops after one pass through the loop.
   * @param {Object} payload - { deck, stem_type, url, start_ms, end_ms }
   */
  async _stemLoopPreview({ deck, stem_type, url, start_ms, end_ms }) {
    console.log(`[DjDeck] Stem loop preview: deck=${deck} type=${stem_type} ${start_ms}ms-${end_ms}ms`)

    // Stop any existing preview
    if (this._previewSource) {
      try { this._previewSource.stop() } catch (_e) { /* already stopped */ }
      this._previewSource = null
    }
    if (this._previewContext) {
      this._previewContext.close().catch(() => {})
      this._previewContext = null
    }

    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      this._previewContext = ctx

      const response = await fetch(url)
      if (!response.ok) {
        console.error(`[DjDeck] Preview fetch failed: HTTP ${response.status}`)
        return
      }

      const arrayBuffer = await response.arrayBuffer()
      const audioBuffer = await ctx.decodeAudioData(arrayBuffer)

      const source = ctx.createBufferSource()
      source.buffer = audioBuffer
      source.connect(ctx.destination)

      const startSec = start_ms / 1000
      const durationSec = (end_ms - start_ms) / 1000

      source.start(0, startSec, durationSec)
      this._previewSource = source

      source.onended = () => {
        this._previewSource = null
        if (this._previewContext) {
          this._previewContext.close().catch(() => {})
          this._previewContext = null
        }
      }
    } catch (err) {
      console.error(`[DjDeck] Stem loop preview failed:`, err)
    }
  },

  _cleanupDeck(deck) {
    const deckState = this.decks[deck]
    if (!deckState) return

    this._stopTimeUpdate(deck)

    // Stop all sources
    Object.values(deckState.stems).forEach(stem => {
      if (stem.source) {
        try { stem.source.stop() } catch (_e) { /* noop */ }
      }
    })

    // Clear beat markers, cue markers and loop region before destroying WaveSurfer
    if (deckState.beatMarkers) {
      deckState.beatMarkers.forEach(m => { try { m.remove() } catch (_e) { /* noop */ } })
      deckState.beatMarkers = []
    }
    this._clearCueMarkers(deck)
    this._clearLoopRegion(deck)

    // Destroy WaveSurfer
    if (deckState.wavesurfer) {
      deckState.wavesurfer.destroy()
      deckState.wavesurfer = null
    }

    // Close AudioContext
    if (deckState.audioContext) {
      deckState.audioContext.close().catch(() => {})
      deckState.audioContext = null
    }

    deckState.masterGain = null
    deckState.stems = {}
    deckState.regionsPlugin = null
    deckState.loopRegion = null
    deckState.cueMarkers = []
    deckState._pendingCuePoints = null
    deckState.loop = null
    deckState.pitch = 0.0
    deckState.tempo = null
    deckState.beatTimes = []
    deckState.beatMarkers = []
    deckState.isPlaying = false
    deckState.pauseOffset = 0
    deckState.duration = 0
  },

  destroyed() {
    console.log("[DjDeck] Hook destroyed, cleaning up")

    // Remove interaction unlock listeners
    if (this._unlockAudio) {
      document.removeEventListener("click", this._unlockAudio)
      document.removeEventListener("touchstart", this._unlockAudio)
      this._unlockAudio = null
    }

    // Remove instant-action listeners
    if (this._onDjPlay) { this.el.removeEventListener("dj:play", this._onDjPlay); this._onDjPlay = null }
    if (this._onDjSeek) { this.el.removeEventListener("dj:seek", this._onDjSeek); this._onDjSeek = null }

    this._cleanupDeck(1)
    this._cleanupDeck(2)

    // Clean up any active stem loop preview
    if (this._previewSource) {
      try { this._previewSource.stop() } catch (_e) { /* already stopped */ }
      this._previewSource = null
    }
    if (this._previewContext) {
      this._previewContext.close().catch(() => {})
      this._previewContext = null
    }
  }
}

export default DjDeck
