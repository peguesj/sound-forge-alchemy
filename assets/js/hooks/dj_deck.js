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
      metronomeOscillator: null, metronomePlaying: false,
      // Loop chaining (Story 2.2)
      _loopChain: null, _loopChainIndex: 0,
      // Cue sequence (Story 2.3)
      _cueSequence: null, _cueSeqActive: false
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
    this.handleEvent("loop_pad_trigger", (payload) => this._triggerLoopPad(payload))
    this.handleEvent("seek_deck", (payload) => this._handleSeekDeck(payload))
    this.handleEvent("set_time_factor", (payload) => this._setTimeFactor(payload))
    this.handleEvent("set_eq_kill", (payload) => this._setEqKill(payload))
    this.handleEvent("set_stem_states", (payload) => this._setStemStates(payload))
    this.handleEvent("toggle_metronome", (payload) => this._toggleMetronome(payload))
    this.handleEvent("set_filter", (payload) => this._setFilter(payload))
    this.handleEvent("set_pitch", (payload) => this._setPitch(payload))
    this.handleEvent("stem_loop_preview", (payload) => this._stemLoopPreview(payload))
    this.handleEvent("set_master_volume", (payload) => this._setMasterVolume(payload))
    this.handleEvent("set_eq_gain", (payload) => this._setEqGain(payload))
    this.handleEvent("download_file", (payload) => this._downloadFile(payload))

    // Tap tempo — delegate clicks on TAP buttons to _handleTapTempo
    this._tapTimes = {}
    this._onTapClick = (e) => {
      const btn = e.target.closest('[id^="tap-tempo-btn-"]')
      if (!btn) return
      const deck = parseInt(btn.id.replace("tap-tempo-btn-", ""), 10)
      if (deck >= 1 && deck <= 4) this._handleTapTempo(deck)
    }
    document.addEventListener("click", this._onTapClick, { passive: true })

    // Stem loop step gate: server tells us which stem + steps pattern for a deck
    this.handleEvent("set_stem_loop_gate", ({ deck, stem_type, steps }) => {
      if (this.decks[deck]) {
        this.decks[deck]._stemLoopGate = { stem_type, steps }
      }
    })

    // Beat-driven step gate, cue sequence, pad sequencer
    this._onBeat = (e) => {
      const { step } = e.detail
      const gateStep = Math.floor(step / 2)  // 16 clock steps → 8 gate positions

      Object.entries(this.decks).forEach(([deckNum, deckState]) => {
        // Stem loop step gate (Story 1.3)
        const gate = deckState._stemLoopGate
        if (gate && deckState.isPlaying) {
          const stem = deckState.stems[gate.stem_type]
          if (stem && stem.gainNode) {
            const userMuted = deckState.stemStates && deckState.stemStates[gate.stem_type] === "mute"
            if (!userMuted) {
              const active = gate.steps[gateStep] !== false
              const now = deckState.audioContext ? deckState.audioContext.currentTime : 0
              stem.gainNode.gain.setValueAtTime(active ? 1.0 : 0.0, now)
            }
          }
        }

        // Cue sequence (Story 2.3): fire seek at each active step
        if (deckState._cueSeqActive && deckState._cueSequence && deckState.isPlaying) {
          const seqLen = deckState._cueSequence.length || 16
          const seqStep = step % seqLen
          const cuePos = deckState._cueSequence[seqStep]
          if (cuePos && cuePos.position_ms != null) {
            this._seekDeck(parseInt(deckNum), cuePos.position_ms / 1000)
          }
        }
      })
    }
    window.addEventListener("sfa:beat", this._onBeat)

    // Loop chain (Story 2.2): ordered list of {start_ms, end_ms} loops to chain
    this.handleEvent("set_loop_chain", ({ deck, loops }) => {
      if (!this.decks[deck]) return
      this.decks[deck]._loopChain = loops && loops.length > 0 ? loops : null
      this.decks[deck]._loopChainIndex = 0
    })

    // Cue sequence (Story 2.3): 16-element array of {position_ms} | null per step
    this.handleEvent("set_cue_sequence", ({ deck, cue_positions, active }) => {
      if (!this.decks[deck]) return
      this.decks[deck]._cueSequence = cue_positions || null
      this.decks[deck]._cueSeqActive = active !== false
    })

    // Grid mode, fraction, and rhythmic quantize
    this.handleEvent("set_grid_mode", ({ deck, mode }) => {
      const canvas = document.getElementById(`smpte-grid-deck-${deck}`)
      if (canvas) canvas.dataset.gridMode = mode
      this._renderSmpteGrid(deck, mode)
    })
    this.handleEvent("set_grid_fraction", ({ deck, fraction }) => {
      const canvas = document.getElementById(`smpte-grid-deck-${deck}`)
      if (canvas) {
        canvas.dataset.gridFraction = fraction
        const mode = canvas.dataset.gridMode || "bar"
        this._renderSmpteGrid(deck, mode)
      }
    })
    this.handleEvent("set_rhythmic_quantize", ({ deck, enabled }) => {
      if (this.decks[deck]) this.decks[deck]._rhythmicQuantize = enabled
    })

    // DJ MIDI Learn
    this._midiLearnActive = false
    this._midiLearnTarget = null
    this._midiLearnListener = null
    // Pre-request MIDI access on first user interaction so requestMIDIAccess
    // is always called within a user-gesture context (browsers block async calls
    // from server-push handlers). We cache the MIDIAccess object here.
    this._midiAccessPromise = null
    this._cachedMidiAccess = null

    const _enumerateMidiDevices = (access) => {
      const inputs = []
      const outputs = []
      access.inputs.forEach(input => {
        inputs.push({
          id: input.id,
          name: input.name || "Unknown Input",
          manufacturer: input.manufacturer || "",
          state: input.state,
          type: "input",
          source: "client"
        })
      })
      access.outputs.forEach(output => {
        outputs.push({
          id: output.id,
          name: output.name || "Unknown Output",
          manufacturer: output.manufacturer || "",
          state: output.state,
          type: "output",
          source: "client"
        })
      })
      const all = [...inputs, ...outputs]
      console.log(`[DjDeck] Client MIDI devices: ${inputs.length} inputs, ${outputs.length} outputs`)
      this.pushEvent("client_midi_devices_updated", { devices: all })
    }

    const _requestMidi = () => {
      if (!this._midiAccessPromise && navigator.requestMIDIAccess) {
        this._midiAccessPromise = navigator.requestMIDIAccess({ sysex: false })
          .then(access => {
            this._cachedMidiAccess = access
            console.log("[DjDeck] MIDI access pre-acquired:", access.inputs.size, "inputs")
            // Report client MIDI devices to server immediately
            _enumerateMidiDevices(access)
            // Re-report on hot-plug / device state change
            access.onstatechange = (event) => {
              console.log(`[DjDeck] MIDI state change: ${event.port?.name} → ${event.port?.state}`)
              _enumerateMidiDevices(access)
            }
            return access
          })
          .catch(err => {
            console.warn("[DjDeck] MIDI pre-request failed:", err)
            this.pushEvent("client_midi_devices_updated", { devices: [], error: err.message })
          })
      }
    }
    // Acquire on first click (user gesture); also try immediately if context is already trusted
    document.addEventListener("click", _requestMidi, { once: true, passive: true })
    // Also attempt on mount — may succeed in browsers that auto-grant MIDI (Chromium flags, extensions)
    if (navigator.requestMIDIAccess) {
      navigator.permissions?.query({ name: "midi" }).then(result => {
        if (result.state === "granted") _requestMidi()
      }).catch(() => { /* permissions API not available */ })
    }

    this.handleEvent("enter_dj_midi_learn", ({ target } = {}) => {
      this._midiLearnTarget = target || null
      this._startMidiLearn()
    })
    this.handleEvent("exit_dj_midi_learn", () => {
      this._midiLearnActive = false
      this._midiLearnTarget = null
      this._stopMidiLearnListener()
    })
    this.handleEvent("dj_learn_assignment_saved", ({ action }) => {
      console.log(`[DjDeck] MIDI Learn: saved mapping for ${action}`)
      // Stay in learn mode, ready for next assignment
      this._startMidiLearn()
    })

    // Instant client-side audio actions — fired via JS.dispatch() before the
    // server round-trip completes. Eliminates the phx-click → server → push_event
    // latency for play/pause and hot cue seeks.
    this._onDjPlay = (e) => this._playDeck({ deck: e.detail.deck, playing: e.detail.playing })
    this._onDjSeek = (e) => this._seekAndPlay({ deck: e.detail.deck, position: e.detail.position })
    this.el.addEventListener("dj:play", this._onDjPlay)
    this.el.addEventListener("dj:seek", this._onDjSeek)

    // Phoenix LiveView morphdom can eject sibling elements (non-component children
    // of the LiveComponent root) to the parent container during component updates.
    // Re-adopt any ejected siblings back into this element after each render.
    this._reattachEjected()
  },

  updated() {
    this._reattachEjected()
  },

  /**
   * After a Phoenix LiveView component update, morphdom may eject inner divs
   * from this hook element to its parent container. This method scans for
   * any such ejected siblings and re-inserts them back into this element.
   *
   * Ejected elements are identified by having `data-phx-loc` attributes
   * (Phoenix template location markers) but NOT having `data-phx-component`
   * (which would mark them as separate LiveComponents with their own lifecycle).
   *
   * LiveComponents (e.g. VirtualController) are intentionally left at the
   * parent level — only plain ejected divs are re-adopted.
   */
  _reattachEjected() {
    const parent = this.el.parentElement
    if (!parent) return

    // Collect direct children of parent that are NOT this element,
    // NOT LiveComponents (data-phx-component), and have data-phx-loc
    // indicating they were rendered as part of this component's template.
    const toAdopt = []
    for (const sibling of Array.from(parent.children)) {
      if (sibling === this.el) continue
      if (sibling.hasAttribute('data-phx-component')) continue  // separate LiveComponent
      if (sibling.hasAttribute('data-phx-loc') && !sibling.hasAttribute('data-phx-view')) {
        // This element has a template location but isn't a LiveView root —
        // it's an ejected inner div from this component's render.
        toAdopt.push(sibling)
      }
    }

    if (toAdopt.length > 0) {
      console.log(`[DjDeck] Re-adopting ${toAdopt.length} ejected element(s) back into dj-tab`)
      for (const el of toAdopt) {
        this.el.appendChild(el)
      }
    }
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

      // Render SMPTE grid canvas overlay
      this._refreshSmpteGrid(deck)

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
      const delay = this._rhythmicQuantizeDelay(deck, deckState.pauseOffset)
      if (delay > 8) {
        console.log(`[DjDeck] Deck ${deck}: rhythmic quantize delay ${delay.toFixed(0)}ms`)
        setTimeout(() => this._startDeck(deck), delay)
      } else {
        this._startDeck(deck)
      }
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

        // Check loop boundary: if loop is active and we've reached loop_end
        if (deckState.loop && deckState.loop.active && deckState.loop.loop_end_ms) {
          if (currentTimeMs >= deckState.loop.loop_end_ms) {
            // Loop chain (Story 2.2): advance to next loop in chain if set
            if (deckState._loopChain && deckState._loopChain.length > 1) {
              deckState._loopChainIndex = (deckState._loopChainIndex + 1) % deckState._loopChain.length
              const nextLoop = deckState._loopChain[deckState._loopChainIndex]
              deckState.loop.loop_start_ms = nextLoop.start_ms
              deckState.loop.loop_end_ms = nextLoop.end_ms
              console.log(`[DjDeck] Deck ${deck}: loop chain → index ${deckState._loopChainIndex} (${nextLoop.start_ms}ms-${nextLoop.end_ms}ms)`)
            }
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
   * Trigger a loop pad: seek to position, optionally set a loop region, apply fade.
   * Supports modes: oneshot (play through once), loop (loop region), gate (play while held).
   */
  async _triggerLoopPad({ deck, pad, position, loop_end, mode, fade }) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState.audioContext) return

    console.log(`[DjDeck] Loop pad ${pad} on deck ${deck}: mode=${mode} pos=${position?.toFixed(2)}s`)

    if (deckState.audioContext.state === 'suspended') {
      try { await deckState.audioContext.resume() } catch (_) {}
    }

    this._seekDeck(deck, position)

    if (mode === 'loop' && loop_end != null) {
      // Arm a loop region
      const loopStart = Math.round(position * 1000)
      const loopEnd = Math.round(loop_end * 1000)
      deckState.loopStartMs = loopStart
      deckState.loopEndMs = loopEnd
      deckState.loopActive = true
    } else if (mode === 'oneshot') {
      // Disable any active loop so it plays through
      deckState.loopActive = false
    }
    // gate mode: server tracks active_pads; no special JS handling needed beyond seek

    if (!deckState.isPlaying) {
      this._startDeck(deck)
    }

    // Apply fade envelope if requested
    if (fade && fade !== 'none') {
      const gainNode = deckState.gainNode
      if (gainNode) {
        const ctx = deckState.audioContext
        const now = ctx.currentTime
        const fadeDuration = 0.25 // 250ms
        if (fade === 'in') {
          gainNode.gain.setValueAtTime(0, now)
          gainNode.gain.linearRampToValueAtTime(deckState._targetGain || 1, now + fadeDuration)
        } else if (fade === 'out') {
          gainNode.gain.setValueAtTime(deckState._targetGain || 1, now)
          gainNode.gain.linearRampToValueAtTime(0, now + fadeDuration)
        } else if (fade === 'cross') {
          gainNode.gain.setValueAtTime(0, now)
          gainNode.gain.linearRampToValueAtTime(deckState._targetGain || 1, now + fadeDuration / 2)
        }
      }
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

  /**
   * Set master volume for all loaded decks.
   * @param {Object} payload - { value: 0-100 }
   */
  _setMasterVolume({ value }) {
    const gainValue = Math.max(0, Math.min(100, value)) / 100
    Object.values(this.decks).forEach(deckState => {
      if (deckState && deckState.masterGain) {
        deckState.masterGain.gain.setValueAtTime(gainValue, deckState.audioContext.currentTime)
      }
    })
    console.log(`[DjDeck] Master volume: ${value}%`)
  },

  /**
   * Set EQ gain for a specific deck and band.
   * @param {Object} payload - { deck, band: "low"|"mid"|"high", gain: -12..12 dB }
   */
  _setEqGain({ deck, band, gain }) {
    const deckState = this.decks[deck]
    if (!deckState) return
    const node = band === "low" ? deckState.eqLow : band === "mid" ? deckState.eqMid : deckState.eqHigh
    if (!node) return
    node.gain.setValueAtTime(gain, deckState.audioContext.currentTime)
    console.log(`[DjDeck] Deck ${deck}: EQ ${band} gain=${gain}dB`)
  },

  /**
   * Trigger a browser file download.
   * @param {Object} payload - { filename, content, mime }
   */
  _downloadFile({ filename, content, mime }) {
    const blob = new Blob([content], { type: mime || "application/octet-stream" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    console.log(`[DjDeck] Downloaded: ${filename}`)
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
    deckState._stemLoopGate = null
    deckState._loopChain = null
    deckState._loopChainIndex = 0
    deckState._cueSequence = null
    deckState._cueSeqActive = false
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
    this._stopMidiLearnListener()
    if (this._onTapClick) {
      document.removeEventListener("click", this._onTapClick)
      this._onTapClick = null
    }
    if (this._onBeat) {
      window.removeEventListener("sfa:beat", this._onBeat)
      this._onBeat = null
    }
    this._stopBeatClock()
  },

  // ---------------------------------------------------------------------------
  // SMPTE Grid Canvas Overlay
  // ---------------------------------------------------------------------------

  /**
   * Format seconds to SMPTE HH:MM:SS timecode.
   */
  _toSmpte(seconds) {
    const h = Math.floor(seconds / 3600)
    const m = Math.floor((seconds % 3600) / 60)
    const s = Math.floor(seconds % 60)
    const pad = (n) => String(n).padStart(2, "0")
    return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
  },

  /**
   * Render the SMPTE grid canvas overlay above the waveform.
   * @param {number} deck
   * @param {string} mode - "bar" | "beat" | "sub" | "smart"
   */
  _renderSmpteGrid(deck, mode) {
    const canvas = document.getElementById(`smpte-grid-deck-${deck}`)
    if (!canvas) return

    const deckState = this.decks[deck]
    const beatTimes = deckState ? (deckState.beatTimes || []) : []
    const duration = deckState ? (deckState.duration || 0) : 0
    const fraction = canvas.dataset.gridFraction || "1/4"
    const showSmpte = canvas.dataset.showSmpte === "true"

    const ctx2d = canvas.getContext("2d")
    const W = canvas.offsetWidth || canvas.width
    const H = canvas.height || 28

    canvas.width = W
    canvas.height = H

    ctx2d.clearRect(0, 0, W, H)

    // Helper: format to SMPTE and draw on bar line
    const drawSmpteLabel = (time, x, alpha) => {
      const label = this._toSmpte(time)
      ctx2d.fillStyle = `rgba(${r},${g},${b},${Math.min(alpha * 1.4, 0.85)})`
      ctx2d.font = "7px monospace"
      ctx2d.fillText(label, x + 2, 8)
    }

    if (beatTimes.length < 2 || duration === 0) {
      // No beat data yet — render simple time ruler with SMPTE labels
      const deckColorFallback = deck === 1 ? [34, 211, 238] : [251, 146, 60]
      const [rf, gf, bf] = deckColorFallback
      ctx2d.font = "7px monospace"
      for (let t = 0; t <= duration; t += 5) {
        const x = (t / duration) * W
        ctx2d.strokeStyle = `rgba(${rf},${gf},${bf},0.2)`
        ctx2d.lineWidth = 1
        ctx2d.beginPath()
        ctx2d.moveTo(x, 0)
        ctx2d.lineTo(x, H)
        ctx2d.stroke()
        ctx2d.fillStyle = `rgba(${rf},${gf},${bf},0.4)`
        ctx2d.fillText(this._toSmpte(t), x + 2, 8)
      }
      return
    }

    const deckColor = deck === 1 ? [34, 211, 238] : [251, 146, 60]
    const [r, g, b] = deckColor

    // Parse fraction (1/1=1, 1/2=2, 1/4=4, 1/8=8, 1/16=16, 1/32=32)
    const fractionDivisor = fraction.includes("/") ? parseInt(fraction.split("/")[1]) : 4

    // Compute bar times (every 4th beat) from beat_times
    const barTimes = beatTimes.filter((_, i) => i % 4 === 0)

    // Pixel density: only label if enough space between lines
    const minLabelSpacing = 45

    const drawLine = (time, alpha, heightRatio, label) => {
      const x = Math.round((time / duration) * W)
      if (x < 0 || x > W) return
      ctx2d.strokeStyle = `rgba(${r},${g},${b},${alpha})`
      ctx2d.lineWidth = 1
      ctx2d.beginPath()
      ctx2d.moveTo(x, H * (1 - heightRatio))
      ctx2d.lineTo(x, H)
      ctx2d.stroke()
      if (label) {
        ctx2d.fillStyle = `rgba(${r},${g},${b},${Math.min(alpha * 1.5, 0.9)})`
        ctx2d.font = "7px monospace"
        ctx2d.fillText(label, x + 2, H - 2)
      }
    }

    if (mode === "bar" || mode === "smart") {
      let lastLabelX = -999
      barTimes.forEach((t, barIdx) => {
        const x = Math.round((t / duration) * W)
        drawLine(t, 0.7, 1.0, `${barIdx + 1}`)
        // SMPTE timestamp on bar lines (if show-smpte or smart mode, and spacing allows)
        if ((showSmpte || mode === "smart") && (x - lastLabelX) >= minLabelSpacing) {
          drawSmpteLabel(t, x, 0.55)
          lastLabelX = x
        }
      })
    }

    if (mode === "beat" || mode === "sub" || mode === "smart") {
      let lastLabelX = -999
      beatTimes.forEach((t, beatIdx) => {
        const isDownbeat = beatIdx % 4 === 0
        if (isDownbeat && (mode === "bar" || mode === "smart")) return
        const x = Math.round((t / duration) * W)
        drawLine(t, 0.3, 0.6, null)
        // SMPTE on every beat if show-smpte and space allows
        if (showSmpte && (x - lastLabelX) >= minLabelSpacing) {
          drawSmpteLabel(t, x, 0.3)
          lastLabelX = x
        }
      })
    }

    if (mode === "sub" || fractionDivisor >= 8) {
      // Sub-beat lines based on the selected fraction
      const divs = fractionDivisor <= 4 ? 4 : fractionDivisor
      for (let i = 0; i < beatTimes.length - 1; i++) {
        const t0 = beatTimes[i]
        const t1 = beatTimes[i + 1]
        const beatDur = t1 - t0
        const subDivs = Math.max(1, divs / 4)
        for (let s = 1; s < subDivs; s++) {
          drawLine(t0 + (beatDur * s / subDivs), 0.1, 0.25, null)
        }
      }
    }
  },

  /**
   * Re-render SMPTE grid after beat data is loaded for a deck.
   */
  _refreshSmpteGrid(deck) {
    const canvas = document.getElementById(`smpte-grid-deck-${deck}`)
    const mode = canvas ? (canvas.dataset.gridMode || "bar") : "bar"
    this._renderSmpteGrid(deck, mode)
  },

  // ---------------------------------------------------------------------------
  // Rhythmic Quantize: snap play start to next beat boundary
  // ---------------------------------------------------------------------------

  /**
   * If rhythmic quantize is enabled for a deck, compute the delay (ms) until
   * the next beat, then schedule the play start after that delay.
   * @param {number} deck
   * @param {number} currentPositionSec - current playback position in seconds
   * @returns {number} delay in milliseconds (0 if quantize disabled or no beats)
   */
  _rhythmicQuantizeDelay(deck, currentPositionSec) {
    const deckState = this.decks[deck]
    if (!deckState || !deckState._rhythmicQuantize) return 0
    const beats = deckState.beatTimes || []
    if (beats.length === 0) return 0

    // Find the next beat after current position
    const nextBeat = beats.find(t => t > currentPositionSec)
    if (!nextBeat) return 0

    const delayMs = (nextBeat - currentPositionSec) * 1000
    // Cap at 1 full bar (4 beats at current tempo) to avoid excessive wait
    const beatInterval = deckState.tempo ? (60 / deckState.tempo * 1000) : 1000
    return Math.min(delayMs, beatInterval * 4)
  },

  // ---------------------------------------------------------------------------
  // DJ MIDI Learn Mode
  // ---------------------------------------------------------------------------

  /**
   * Start capturing the next incoming MIDI message for learn assignment.
   */
  async _startMidiLearn() {
    this._midiLearnActive = true
    this._stopMidiLearnListener()

    if (!navigator.requestMIDIAccess) {
      console.warn("[DjDeck] Web MIDI API not available")
      return
    }

    try {
      // Use cached MIDI access if available (avoids non-gesture context restriction).
      // If not yet cached, request now (may fail in some browsers outside gesture context).
      const midiAccess = this._cachedMidiAccess ||
        await (this._midiAccessPromise ||
          (this._midiAccessPromise = navigator.requestMIDIAccess({ sysex: false })
            .then(a => { this._cachedMidiAccess = a; return a })))
      this._midiLearnMidiAccess = midiAccess

      this._midiLearnListener = (event) => {
        if (!this._midiLearnActive) return

        const [status, data1, data2] = event.data
        const statusType = status & 0xF0
        const channel = status & 0x0F

        let midiType = null
        let number = data1
        let value = data2

        if (statusType === 0x90 && value > 0) {
          midiType = "note_on"
        } else if (statusType === 0xB0) {
          midiType = "cc"
        } else {
          return // ignore other message types
        }

        const deviceName = event.target?.name || "Unknown MIDI Device"

        const target = this._midiLearnTarget || {}
        const payload = {
          device_name: deviceName,
          midi_type: midiType,
          channel: channel,
          number: number,
          action: target.action || "dj_play",
          deck: target.deck || null,
          slot: target.slot || null
        }

        console.log("[DjDeck] MIDI Learn captured:", payload)
        this.pushEvent("dj_midi_learned", payload)
      }

      // Attach listener to all MIDI inputs
      midiAccess.inputs.forEach(input => {
        input.onmidimessage = this._midiLearnListener
      })

      console.log("[DjDeck] MIDI Learn: listening on", midiAccess.inputs.size, "inputs")
    } catch (err) {
      console.error("[DjDeck] MIDI Learn: failed to get MIDI access:", err)
    }
  },

  /**
   * Remove the MIDI learn message listener from all inputs.
   */
  _stopMidiLearnListener() {
    if (this._midiLearnMidiAccess) {
      this._midiLearnMidiAccess.inputs.forEach(input => {
        if (input.onmidimessage === this._midiLearnListener) {
          input.onmidimessage = null
        }
      })
    }
    this._midiLearnListener = null
    this._midiLearnMidiAccess = null
  },

  // -- Tap Tempo --

  /**
   * Handle a tap from the TAP button for a given deck.
   * Accumulates up to 8 tap timestamps, computes average BPM,
   * and pushes a `tap_tempo` event to the server.
   * Resets if more than 2 seconds have elapsed since the last tap.
   *
   * @param {number} deck - deck number (1–4)
   */
  _handleTapTempo(deck) {
    const now = performance.now()
    if (!this._tapTimes) this._tapTimes = {}
    if (!this._tapTimes[deck]) this._tapTimes[deck] = []

    const taps = this._tapTimes[deck]

    // Reset if gap > 2 seconds
    if (taps.length > 0 && now - taps[taps.length - 1] > 2000) {
      this._tapTimes[deck] = []
    }

    this._tapTimes[deck].push(now)

    // Keep only the last 8 taps
    if (this._tapTimes[deck].length > 8) {
      this._tapTimes[deck] = this._tapTimes[deck].slice(-8)
    }

    if (this._tapTimes[deck].length < 2) return  // Need at least 2 taps

    // Compute average interval in ms
    const times = this._tapTimes[deck]
    let totalInterval = 0
    for (let i = 1; i < times.length; i++) {
      totalInterval += times[i] - times[i - 1]
    }
    const avgInterval = totalInterval / (times.length - 1)
    const tappedBpm = Math.round((60000 / avgInterval) * 10) / 10

    if (tappedBpm > 20 && tappedBpm < 400) {
      console.log(`[DjDeck] Tap tempo deck ${deck}: ${tappedBpm} BPM`)
      this.pushEvent("tap_tempo", { deck: String(deck), bpm: String(tappedBpm) })
    }
  },

  // -- Global Beat Clock (shared singleton for step sequencer hooks) --

  /**
   * Start the global beat clock at the given BPM.
   * Publishes `window.__sfaBeatClock` for other hooks (pad sequencer, stem gating).
   * Only deck 1's BPM drives the master clock; other decks may use their own.
   *
   * @param {number} bpm - beats per minute
   */
  _startBeatClock(bpm) {
    this._stopBeatClock()
    if (!bpm || bpm <= 0) return

    const beatMs = 60000 / bpm
    let step = 0

    window.__sfaBeatClock = { bpm, step: 0, active: true }

    this._beatClockInterval = setInterval(() => {
      step = (step + 1) % 16
      window.__sfaBeatClock.step = step
      window.__sfaBeatClock.bpm = bpm
      // Dispatch a custom event so other hooks can react without polling
      window.dispatchEvent(new CustomEvent("sfa:beat", { detail: { step, bpm } }))
    }, beatMs)
  },

  _stopBeatClock() {
    if (this._beatClockInterval) {
      clearInterval(this._beatClockInterval)
      this._beatClockInterval = null
    }
    if (window.__sfaBeatClock) {
      window.__sfaBeatClock.active = false
    }
  }
}

export default DjDeck
