/**
 * AudioPlayer Hook - Multi-stem Web Audio API player with WaveSurfer waveform
 *
 * Loads multiple audio stems and plays them simultaneously with
 * independent volume control per stem, solo, and mute.
 * Renders a waveform visualization using WaveSurfer.js for the first stem.
 */
import WaveSurfer from "wavesurfer.js"

const AudioPlayer = {
  mounted() {
    console.log("[AudioPlayer] Hook mounted")
    this.audioContext = null
    this.stems = {}
    this.wavesurfer = null
    this.isPlaying = false
    this.startTime = 0
    this.pauseOffset = 0
    this._initialized = false

    this._loadStems()
  },

  updated() {
    // Re-initialize if data-stems changed (LiveView re-render)
    const newData = this.el.dataset.stems || "[]"
    if (newData !== this._lastStemData) {
      console.log("[AudioPlayer] data-stems changed, reinitializing")
      this._cleanup()
      this._loadStems()
    }
  },

  _loadStems() {
    // Parse stem data from data attribute
    const stemData = JSON.parse(this.el.dataset.stems || "[]")
    this._lastStemData = this.el.dataset.stems || "[]"
    console.log("[AudioPlayer] Parsed stem data:", stemData)

    if (stemData.length > 0) {
      this._setLoadingText(`Loading ${stemData.length} stems...`)
      this.initAudioContext(stemData)
    } else {
      console.warn("[AudioPlayer] No stems available")
    }

    if (this._initialized) return
    this._initialized = true

    // Handle LiveView events from server
    this.handleEvent("toggle_play", () => this.togglePlay())
    this.handleEvent("seek", ({ time }) => this.seek(time))
    this.handleEvent("set_volume", ({ level }) => this.setMasterVolume(level / 100))
    this.handleEvent("set_stem_volume", ({ stem, level }) => this.setStemVolume(stem, level / 100))
    this.handleEvent("mute_stem", ({ stem, muted }) => this.muteStem(stem, muted))
    this.handleEvent("solo_stem", ({ stem }) => this.soloStem(stem))

    // Handle DOM events and forward to LiveView
    this.handleDOMEvents()

    // Initialize transport bridge for TransportBar coordination
    this._setupTransportListener()
    this._updateTransportBridge(0)

    // Keyboard shortcuts (only when not typing in an input)
    this._keyHandler = (e) => {
      const tag = e.target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

      switch (e.key) {
        case " ":
          e.preventDefault()
          this.pushEvent("toggle_play", {})
          break
        case "ArrowLeft":
          e.preventDefault()
          if (this.audioContext) {
            const cur = this.isPlaying
              ? this.audioContext.currentTime - this.startTime
              : this.pauseOffset
            this.seek(Math.max(0, cur - 5))
          }
          break
        case "ArrowRight":
          e.preventDefault()
          if (this.audioContext && this.duration) {
            const cur = this.isPlaying
              ? this.audioContext.currentTime - this.startTime
              : this.pauseOffset
            this.seek(Math.min(this.duration, cur + 5))
          }
          break
        case "ArrowUp":
          e.preventDefault()
          this.pushEvent("master_volume", { level: Math.min(100, (this.masterGain?.gain.value || 0.8) * 100 + 5).toString() })
          break
        case "ArrowDown":
          e.preventDefault()
          this.pushEvent("master_volume", { level: Math.max(0, (this.masterGain?.gain.value || 0.8) * 100 - 5).toString() })
          break
        case "m":
        case "M":
          e.preventDefault()
          if (this.masterGain) {
            if (this._preMuteVolume != null) {
              this.masterGain.gain.setValueAtTime(this._preMuteVolume, this.audioContext.currentTime)
              this._preMuteVolume = null
            } else {
              this._preMuteVolume = this.masterGain.gain.value
              this.masterGain.gain.setValueAtTime(0, this.audioContext.currentTime)
            }
          }
          break
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  },

  handleDOMEvents() {
    // This method is called from mounted() to set up event listeners
    // No DOM event forwarding needed since LiveComponent handles phx-click events
  },

  _setLoadingText(text) {
    const loadingEl = this.el.querySelector("[id^='waveform-loading-']")
    if (loadingEl) {
      loadingEl.querySelector("span").textContent = text
    }
  },

  _hideLoading() {
    const loadingEl = this.el.querySelector("[id^='waveform-loading-']")
    if (loadingEl) loadingEl.style.display = "none"
  },

  _cleanup() {
    this.stopTimeUpdate()
    Object.values(this.stems).forEach(stem => {
      if (stem.source) stem.source.stop()
    })
    if (this.wavesurfer) {
      this.wavesurfer.destroy()
      this.wavesurfer = null
    }
    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }
    this.stems = {}
    this.isPlaying = false
    this.pauseOffset = 0
  },

  async initAudioContext(stemData) {
    console.log("[AudioPlayer] Initializing audio context with stems:", stemData)

    try {
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
      this.masterGain = this.audioContext.createGain()
      this.masterGain.connect(this.audioContext.destination)
      this.masterGain.gain.value = 0.8

      let loaded = 0
      const total = stemData.length

      // Load all stems in parallel
      const loadPromises = stemData.map(async (stem) => {
        try {
          console.log(`[AudioPlayer] Fetching stem ${stem.type} from ${stem.url}`)
          const response = await fetch(stem.url)
          if (!response.ok) {
            console.error(`[AudioPlayer] Failed to fetch stem ${stem.type}: HTTP ${response.status} for ${stem.url}`)
            this._setLoadingText(`Failed to load ${stem.type} (HTTP ${response.status})`)
            return
          }
          const arrayBuffer = await response.arrayBuffer()
          const audioBuffer = await this.audioContext.decodeAudioData(arrayBuffer)

          const gainNode = this.audioContext.createGain()
          gainNode.connect(this.masterGain)

          this.stems[stem.type] = {
            buffer: audioBuffer,
            gainNode: gainNode,
            source: null,
            volume: 1.0,
            muted: false,
            url: stem.url
          }
          loaded++
          this._setLoadingText(`Loading stems ${loaded}/${total}...`)
          console.log(`[AudioPlayer] Successfully loaded stem ${stem.type} (${loaded}/${total})`)
        } catch (err) {
          console.error(`[AudioPlayer] Failed to load stem ${stem.type}:`, err)
          this._setLoadingText(`Error loading ${stem.type}: ${err.message}`)
        }
      })

      await Promise.all(loadPromises)
      console.log("[AudioPlayer] All stems loaded:", Object.keys(this.stems))
    } catch (err) {
      console.error("[AudioPlayer] Failed to initialize audio context:", err)
      return
    }

    // Check if any stems were actually loaded
    const loadedCount = Object.keys(this.stems).length
    if (loadedCount === 0) {
      console.error("[AudioPlayer] No stems could be loaded")
      this._setLoadingText("Failed to load stems - check file paths")
      return
    }

    // Report duration from the longest stem
    const durations = Object.values(this.stems).map(s => s.buffer.duration)
    const maxDuration = Math.max(...durations, 0)
    this.duration = maxDuration
    console.log("[AudioPlayer] Duration:", maxDuration)
    this._setLoadingText("Rendering waveform...")
    this.pushEvent("player_ready", { duration: maxDuration })
    this._updateTransportBridge(0)

    // Initialize WaveSurfer waveform using the first stem (vocals preferred)
    this.initWaveform(stemData)
  },

  initWaveform(stemData) {
    console.log("[AudioPlayer] Initializing waveform")
    // Use a more specific selector to avoid matching the loading overlay
    const waveformEl = this.el.querySelector("[id^='waveform-']:not([id*='loading'])")
    if (!waveformEl) {
      console.error("[AudioPlayer] Waveform element not found")
      this._setLoadingText("Waveform container not found")
      return
    }
    console.log("[AudioPlayer] Found waveform element:", waveformEl.id)

    // Prefer vocals stem URL for waveform, fallback to first available
    const vocalsUrl = stemData.find(s => s.type === "vocals")?.url
    const firstUrl = stemData[0]?.url
    const waveformUrl = vocalsUrl || firstUrl

    if (!waveformUrl) {
      console.error("[AudioPlayer] No waveform URL available")
      this._setLoadingText("No audio available for waveform")
      return
    }

    console.log("[AudioPlayer] Creating WaveSurfer with URL:", waveformUrl)
    this.wavesurfer = WaveSurfer.create({
      container: waveformEl,
      waveColor: "#6b7280",
      progressColor: "#a855f7",
      cursorColor: "#c084fc",
      height: 80,
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      interact: true,
      url: waveformUrl,
      normalize: true
    })

    // Mute wavesurfer's own audio - we use our Web Audio API stems instead
    this.wavesurfer.on("ready", () => {
      console.log("[AudioPlayer] WaveSurfer ready - waveform rendered")
      this.wavesurfer.setMuted(true)
      this._hideLoading()
    })

    this.wavesurfer.on("loading", (percent) => {
      this._setLoadingText(`Rendering waveform ${percent}%...`)
    })

    this.wavesurfer.on("error", (error) => {
      console.error("[AudioPlayer] WaveSurfer error:", error)
      this._setLoadingText("Waveform failed - stems still playable")
    })

    // Handle click-to-seek on the waveform
    // v7: interaction event passes time in seconds
    this.wavesurfer.on("interaction", (newTime) => {
      console.log("[AudioPlayer] Waveform seek to:", newTime)
      this.seek(newTime)
      this.pushEvent("time_update", { time: newTime })
    })
  },

  togglePlay() {
    if (!this.audioContext) return

    if (this.audioContext.state === "suspended") {
      this.audioContext.resume()
    }

    if (this.isPlaying) {
      this.pause()
    } else {
      this.play()
    }
  },

  play() {
    if (this.isPlaying) return

    // Create new source nodes for each stem
    Object.entries(this.stems).forEach(([type, stem]) => {
      const source = this.audioContext.createBufferSource()
      source.buffer = stem.buffer
      source.connect(stem.gainNode)
      source.start(0, this.pauseOffset)
      stem.source = source
    })

    this.startTime = this.audioContext.currentTime - this.pauseOffset
    this.isPlaying = true
    this.startTimeUpdate()
  },

  pause() {
    if (!this.isPlaying) return

    this.pauseOffset = this.audioContext.currentTime - this.startTime

    Object.values(this.stems).forEach(stem => {
      if (stem.source) {
        stem.source.stop()
        stem.source = null
      }
    })

    this.isPlaying = false
    this.stopTimeUpdate()
  },

  seek(time) {
    const wasPlaying = this.isPlaying
    if (wasPlaying) this.pause()
    this.pauseOffset = time
    if (wasPlaying) this.play()

    // Update waveform cursor position
    if (this.wavesurfer && this.duration > 0) {
      this.wavesurfer.seekTo(time / this.duration)
    }

    this.pushEvent("time_update", { time })
  },

  setMasterVolume(level) {
    if (this.masterGain) {
      this.masterGain.gain.setValueAtTime(level, this.audioContext.currentTime)
    }
  },

  setStemVolume(stemType, level) {
    const stem = this.stems[stemType]
    if (stem) {
      stem.volume = level
      if (!stem.muted) {
        stem.gainNode.gain.setValueAtTime(level, this.audioContext.currentTime)
      }
    }
  },

  muteStem(stemType, muted) {
    const stem = this.stems[stemType]
    if (stem) {
      stem.muted = muted
      const volume = muted ? 0 : stem.volume
      stem.gainNode.gain.setValueAtTime(volume, this.audioContext.currentTime)
    }
  },

  soloStem(stemType) {
    Object.entries(this.stems).forEach(([type, stem]) => {
      if (stemType) {
        const volume = type === stemType ? stem.volume : 0
        stem.gainNode.gain.setValueAtTime(volume, this.audioContext.currentTime)
      } else {
        const volume = stem.muted ? 0 : stem.volume
        stem.gainNode.gain.setValueAtTime(volume, this.audioContext.currentTime)
      }
    })
  },

  startTimeUpdate() {
    this.timeUpdateInterval = setInterval(() => {
      if (this.isPlaying && this.audioContext) {
        const currentTime = this.audioContext.currentTime - this.startTime
        if (currentTime >= this.duration) {
          this.pause()
          this.pauseOffset = 0
          this.pushEvent("time_update", { time: 0 })
          if (this.wavesurfer) this.wavesurfer.seekTo(0)
          this._updateTransportBridge(0)
        } else {
          this.pushEvent("time_update", { time: currentTime })
          // Sync waveform cursor
          if (this.wavesurfer && this.duration > 0) {
            this.wavesurfer.seekTo(currentTime / this.duration)
          }
          this._updateTransportBridge(currentTime)
        }
      }
    }, 250)
  },

  stopTimeUpdate() {
    if (this.timeUpdateInterval) {
      clearInterval(this.timeUpdateInterval)
      this.timeUpdateInterval = null
    }
  },

  /**
   * Update the global transport bridge so TransportBar can read our state.
   */
  _updateTransportBridge(currentTime) {
    window.__audioPlayerTransport = {
      currentTime: currentTime,
      duration: this.duration || 0,
      playing: this.isPlaying,
    }
  },

  /**
   * Set up listener for transport commands from TransportBar.
   */
  _setupTransportListener() {
    this._transportHandler = (e) => {
      const { command, tab } = e.detail || {}
      if (tab !== "library") return

      switch (command) {
        case "play":
          if (!this.isPlaying) this.togglePlay()
          break
        case "pause":
          if (this.isPlaying) this.togglePlay()
          break
        case "stop":
          if (this.isPlaying) this.pause()
          this.pauseOffset = 0
          if (this.wavesurfer) this.wavesurfer.seekTo(0)
          this._updateTransportBridge(0)
          break
        case "seek":
          if (e.detail.time !== undefined) {
            this.seek(e.detail.time)
          }
          break
        case "volume":
          if (e.detail.level !== undefined) {
            this.setMasterVolume(e.detail.level / 100)
          }
          break
      }
    }
    window.addEventListener("sfa:transport", this._transportHandler)
  },

  destroyed() {
    if (this._keyHandler) {
      document.removeEventListener("keydown", this._keyHandler)
    }
    if (this._transportHandler) {
      window.removeEventListener("sfa:transport", this._transportHandler)
    }
    delete window.__audioPlayerTransport
    this._cleanup()
  }
}

export default AudioPlayer
