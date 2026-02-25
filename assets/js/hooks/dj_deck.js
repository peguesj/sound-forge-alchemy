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

const DjDeck = {
  mounted() {
    console.log("[DjDeck] Hook mounted")

    // Deck audio state: keyed by deck number (1, 2)
    this.decks = {
      1: { audioContext: null, masterGain: null, stems: {}, wavesurfer: null, regionsPlugin: null, loopRegion: null, cueMarkers: [], isPlaying: false, startTime: 0, pauseOffset: 0, duration: 0, loop: null, pitch: 0.0, tempo: null, beatTimes: [], beatMarkers: [] },
      2: { audioContext: null, masterGain: null, stems: {}, wavesurfer: null, regionsPlugin: null, loopRegion: null, cueMarkers: [], isPlaying: false, startTime: 0, pauseOffset: 0, duration: 0, loop: null, pitch: 0.0, tempo: null, beatTimes: [], beatMarkers: [] }
    }

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
    this.handleEvent("set_pitch", (payload) => this._setPitch(payload))
    this.handleEvent("stem_loop_preview", (payload) => this._stemLoopPreview(payload))
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

    if (!urls || urls.length === 0) {
      console.warn(`[DjDeck] No audio URLs for deck ${deck}`)
      return
    }

    try {
      // Create a fresh AudioContext for this deck
      const ctx = new (window.AudioContext || window.webkitAudioContext)()
      const masterGain = ctx.createGain()
      masterGain.connect(ctx.destination)
      masterGain.gain.value = 1.0

      deckState.audioContext = ctx
      deckState.masterGain = masterGain
      deckState.stems = {}

      // Load all audio sources in parallel
      const loadPromises = urls.map(async (item) => {
        try {
          const response = await fetch(item.url)
          if (!response.ok) {
            console.error(`[DjDeck] Deck ${deck}: HTTP ${response.status} for ${item.url}`)
            return
          }
          const arrayBuffer = await response.arrayBuffer()
          const audioBuffer = await ctx.decodeAudioData(arrayBuffer)

          const gainNode = ctx.createGain()
          gainNode.connect(masterGain)

          deckState.stems[item.type] = {
            buffer: audioBuffer,
            gainNode: gainNode,
            source: null
          }
        } catch (err) {
          console.error(`[DjDeck] Deck ${deck}: failed to load ${item.type}:`, err)
        }
      })

      await Promise.all(loadPromises)

      // Determine duration from longest buffer
      const durations = Object.values(deckState.stems).map(s => s.buffer.duration)
      deckState.duration = Math.max(...durations, 0)
      console.log(`[DjDeck] Deck ${deck}: loaded ${Object.keys(deckState.stems).length} sources, duration=${deckState.duration.toFixed(1)}s`)

      // Initialize WaveSurfer (visual only)
      this._initWaveform(deck, urls)

      // Apply current crossfader balance
      this._applyCrossfader()

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
  _playDeck({ deck, playing }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    if (deckState.audioContext.state === "suspended") {
      deckState.audioContext.resume()
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

    // Apply stored pitch to all newly created source nodes
    const rate = 1.0 + (deckState.pitch / 100.0)
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
  _seekAndPlay({ deck, position }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    console.log(`[DjDeck] Deck ${deck}: seek_and_play to ${position.toFixed(2)}s`)

    // Resume AudioContext if suspended (browser autoplay policy)
    if (deckState.audioContext.state === "suspended") {
      deckState.audioContext.resume()
    }

    // Seek to position
    this._seekDeck(deck, position)

    // Start playback if not already playing
    if (!deckState.isPlaying) {
      this._startDeck(deck)
    }
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
