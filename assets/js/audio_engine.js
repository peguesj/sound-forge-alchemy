/**
 * Global audio engine singleton — survives LiveView hook lifecycle.
 *
 * Owns all AudioContext objects so that hook `destroyed()` callbacks do not
 * kill active audio playback when the user navigates away from the DJ tab.
 * The singleton is initialised once per page load and intentionally never
 * destroyed.
 *
 * Per-deck state shape:
 *   {
 *     audioContext: AudioContext | null,
 *     masterGain:   GainNode | null,
 *     eqLow:        BiquadFilterNode | null,
 *     eqMid:        BiquadFilterNode | null,
 *     eqHigh:       BiquadFilterNode | null,
 *     deckFilter:   BiquadFilterNode | null,
 *     stems:        { [type: string]: { buffer, gainNode, source } },
 *     isPlaying:    boolean,
 *     startTime:    number,   // audioCtx.currentTime at last play start
 *     pauseOffset:  number,   // seconds into the track when paused
 *     duration:     number,
 *     timeFactor:   number,
 *     pitch:        number,
 *   }
 */
const AudioEngine = (() => {
  // Per-deck state — keyed by deck number (1, 2, 3, 4)
  const _decks = {}

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  function _ensureDeck(deckNum) {
    if (!_decks[deckNum]) {
      _decks[deckNum] = {
        audioContext: null,
        masterGain: null,
        eqLow: null,
        eqMid: null,
        eqHigh: null,
        deckFilter: null,
        stems: {},
        isPlaying: false,
        startTime: 0,
        pauseOffset: 0,
        duration: 0,
        timeFactor: 1.0,
        pitch: 0.0,
        _audioReady: false,
        _pendingPlay: false,
        _pendingCuePoints: null,
        _stemLoopGate: null,
        _loopChain: null,
        _loopChainIndex: 0,
        _cueSequence: null,
        _cueSeqActive: false,
        _rhythmicQuantize: false,
        loop: null,
        tempo: null,
        beatTimes: [],
        beatMarkers: [],
        cueMarkers: [],
        wavesurfer: null,
        regionsPlugin: null,
        loopRegion: null,
      }
    }
    return _decks[deckNum]
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  return {
    /**
     * Return (or lazily create) the AudioContext owned by a specific deck.
     * Each deck gets its own AudioContext so crossfader gain adjustments are
     * independent and the EQ chain is isolated per deck.
     *
     * @param {number} deckNum
     * @returns {AudioContext}
     */
    getContext(deckNum) {
      const deck = _ensureDeck(deckNum)
      if (!deck.audioContext) {
        deck.audioContext = new (window.AudioContext || window.webkitAudioContext)()
        console.log(`[AudioEngine] Created AudioContext for deck ${deckNum}`)
      }
      return deck.audioContext
    },

    /**
     * Return the full state object for a deck, creating it if needed.
     *
     * @param {number} deckNum
     * @returns {object}
     */
    getDeck(deckNum) {
      return _ensureDeck(deckNum)
    },

    /**
     * Merge partial state into the deck state.  Used by the hook to persist
     * state back into the singleton before `destroyed()` returns.
     *
     * @param {number} deckNum
     * @param {object} partialState
     */
    setDeck(deckNum, partialState) {
      const deck = _ensureDeck(deckNum)
      Object.assign(deck, partialState)
    },

    /**
     * Return the master gain node for a deck, lazily creating it and wiring
     * it through the standard EQ chain if the AudioContext already exists.
     *
     * Call this AFTER getContext() so the AudioContext is available.
     *
     * @param {number} deckNum
     * @returns {GainNode | null}
     */
    getMasterGain(deckNum) {
      return _ensureDeck(deckNum).masterGain
    },

    /**
     * Set the master volume (0–100) for a deck by adjusting the masterGain
     * node.
     *
     * @param {number} deckNum
     * @param {number} vol  0–100
     */
    setMasterVolume(deckNum, vol) {
      const deck = _ensureDeck(deckNum)
      if (deck.masterGain) {
        deck.masterGain.gain.setValueAtTime(vol / 100, deck.audioContext.currentTime)
      }
    },

    /**
     * Stop sources and record the pauseOffset so playback can resume from the
     * same position.
     *
     * @param {number} deckNum
     */
    pauseDeck(deckNum) {
      const deck = _ensureDeck(deckNum)
      if (!deck.isPlaying || !deck.audioContext) return

      deck.pauseOffset = deck.audioContext.currentTime - deck.startTime

      Object.values(deck.stems).forEach(stem => {
        if (stem.source) {
          try { stem.source.stop() } catch (_e) { /* already stopped */ }
          stem.source = null
        }
      })

      deck.isPlaying = false
    },

    /**
     * Resume playback from the current pauseOffset.
     *
     * @param {number} deckNum
     */
    resumeDeck(deckNum) {
      const deck = _ensureDeck(deckNum)
      if (deck.isPlaying || !deck.audioContext) return

      Object.entries(deck.stems).forEach(([_type, stem]) => {
        const source = deck.audioContext.createBufferSource()
        source.buffer = stem.buffer
        source.connect(stem.gainNode)
        source.start(0, deck.pauseOffset)
        stem.source = source
      })

      const timeFactor = deck.timeFactor || 1.0
      const rate = timeFactor * (1.0 + (deck.pitch / 100.0))
      if (rate !== 1.0) {
        Object.values(deck.stems).forEach(stem => {
          if (stem.source) {
            stem.source.playbackRate.setValueAtTime(rate, deck.audioContext.currentTime)
          }
        })
      }

      deck.startTime = deck.audioContext.currentTime - deck.pauseOffset
      deck.isPlaying = true
    },

    /**
     * Seek the deck to the given position in milliseconds.  Restarts playback
     * from the new position if the deck was already playing.
     *
     * @param {number} deckNum
     * @param {number} posMs
     */
    seekDeck(deckNum, posMs) {
      const deck = _ensureDeck(deckNum)
      if (!deck.audioContext) return

      const wasPlaying = deck.isPlaying
      if (wasPlaying) this.pauseDeck(deckNum)
      deck.pauseOffset = posMs / 1000
      if (wasPlaying) this.resumeDeck(deckNum)
    },

    /**
     * @param {number} deckNum
     * @returns {boolean}
     */
    isPlaying(deckNum) {
      return !!_decks[deckNum]?.isPlaying
    },

    /**
     * Return the live playhead position in milliseconds for the deck, using
     * the AudioContext clock rather than a stale server value.
     *
     * @param {number} deckNum
     * @returns {number}
     */
    getLivePositionMs(deckNum) {
      const deck = _decks[deckNum]
      if (!deck || !deck.audioContext) return 0
      if (!deck.isPlaying) return (deck.pauseOffset || 0) * 1000
      return (deck.audioContext.currentTime - deck.startTime) * 1000
    },

    /**
     * No-op.  The singleton is never destroyed — it outlives any hook.
     */
    destroy() {
      // Intentional no-op: singleton survives LiveView navigation.
    },
  }
})()

export default AudioEngine
