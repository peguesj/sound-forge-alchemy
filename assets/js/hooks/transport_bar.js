/**
 * TransportBar Hook - SMPTE transport control JS integration
 *
 * Coordinates with the TransportBarComponent LiveComponent to provide:
 * - Smooth SMPTE timecode updates via requestAnimationFrame
 * - Keyboard shortcuts (Space, Home, End, arrow keys)
 * - Scrub bar click-to-seek
 * - Bridge events between transport and active audio engines
 *   (DawPreview, DjDeck, AudioPlayer)
 *
 * Listens for `transport_command` push events from the server and relays
 * them to the active audio engine. Sends `transport_time_update` and
 * `transport_duration` events back to the server.
 */
const TransportBar = {
  mounted() {
    this.navTab = this.el.dataset.navTab || "library"
    this.fps = parseInt(this.el.dataset.fps || "30", 10)
    this.isPlaying = false
    this.currentTime = 0
    this.duration = 0
    this._rafId = null
    this._lastUpdateTime = 0

    // Cache DOM elements
    this.smpteDisplay = this.el.querySelector("[id^='smpte-display-']")
    this.scrubBar = this.el.querySelector("[id^='scrub-bar-']")
    this.progressBar = this.scrubBar
      ? this.scrubBar.querySelector(".bg-gradient-to-r")
      : null

    this._setupScrubBar()
    this._setupKeyboardShortcuts()
    this._setupAudioBridge()
    this._listenForTransportCommands()
  },

  updated() {
    // Re-read nav tab in case it changed
    this.navTab = this.el.dataset.navTab || "library"
  },

  /**
   * Set up click-to-seek on the scrub bar.
   */
  _setupScrubBar() {
    if (!this.scrubBar) return

    // Click to seek
    this.scrubBar.addEventListener("click", (e) => {
      const rect = this.scrubBar.getBoundingClientRect()
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
      const position = x / rect.width
      this.pushEvent("transport_seek", { position: position })
    })

    // Drag to scrub
    let isDragging = false
    this.scrubBar.addEventListener("mousedown", (e) => {
      isDragging = true
      e.preventDefault()
    })

    document.addEventListener("mousemove", (e) => {
      if (!isDragging) return
      const rect = this.scrubBar.getBoundingClientRect()
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
      const position = x / rect.width
      this._updateProgressVisual(position * 100)
      this._updateSmpteVisual(position * this.duration)
    })

    document.addEventListener("mouseup", (e) => {
      if (!isDragging) return
      isDragging = false
      const rect = this.scrubBar.getBoundingClientRect()
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
      const position = x / rect.width
      this.pushEvent("transport_seek", { position: position })
    })
  },

  /**
   * Set up keyboard shortcuts for transport control.
   */
  _setupKeyboardShortcuts() {
    this._keyHandler = (e) => {
      const tag = e.target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

      switch (e.key) {
        case " ":
          e.preventDefault()
          this.pushEvent("transport_play", {})
          break
        case "Home":
          e.preventDefault()
          this.pushEvent("transport_rewind_start", {})
          break
        case "End":
          e.preventDefault()
          if (this.duration > 0) {
            this.pushEvent("transport_seek", { position: 0.999 })
          }
          break
        case "ArrowLeft":
          // Let arrow keys pass through if we are not focused on transport
          if (!e.shiftKey) return
          e.preventDefault()
          this.pushEvent("transport_rewind", {})
          break
        case "ArrowRight":
          if (!e.shiftKey) return
          e.preventDefault()
          this.pushEvent("transport_ff", {})
          break
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  },

  /**
   * Bridge between the transport bar and the active audio engine.
   * Polls the active audio engine for time updates during playback.
   */
  _setupAudioBridge() {
    // Poll time from active audio engine
    this._pollInterval = setInterval(() => {
      const timeInfo = this._getActiveEngineTime()
      if (timeInfo) {
        if (timeInfo.duration > 0 && timeInfo.duration !== this.duration) {
          this.duration = timeInfo.duration
          this.pushEvent("transport_duration", { duration: timeInfo.duration })
        }
        if (this.isPlaying && timeInfo.currentTime !== undefined) {
          this.currentTime = timeInfo.currentTime
          this.pushEvent("transport_time_update", { time: timeInfo.currentTime })
        }
      }
    }, 200)

    // Use requestAnimationFrame for smooth SMPTE display
    this._startSmpteUpdate()
  },

  /**
   * Start the smooth SMPTE timecode animation loop.
   * Updates the SMPTE display at screen refresh rate for smooth counting.
   */
  _startSmpteUpdate() {
    const update = () => {
      if (this.isPlaying) {
        const timeInfo = this._getActiveEngineTime()
        if (timeInfo && timeInfo.currentTime !== undefined) {
          this.currentTime = timeInfo.currentTime
          this._updateSmpteVisual(this.currentTime)
          this._updateProgressVisual(
            this.duration > 0
              ? (this.currentTime / this.duration) * 100
              : 0
          )
        }
      }
      this._rafId = requestAnimationFrame(update)
    }
    this._rafId = requestAnimationFrame(update)
  },

  /**
   * Update the SMPTE display element directly (bypassing LiveView for smoothness).
   */
  _updateSmpteVisual(timeSec) {
    if (!this.smpteDisplay) return
    this.smpteDisplay.textContent = this._formatSmpte(timeSec)
  },

  /**
   * Update the progress bar width directly.
   */
  _updateProgressVisual(percent) {
    if (!this.progressBar) return
    this.progressBar.style.width = `${Math.min(100, Math.max(0, percent))}%`
  },

  /**
   * Format seconds as SMPTE timecode HH:MM:SS:FF.
   */
  _formatSmpte(seconds) {
    if (!seconds || seconds < 0) return "00:00:00:00"
    const totalFrames = Math.floor(seconds * this.fps)
    const frames = totalFrames % this.fps
    const totalSecs = Math.floor(totalFrames / this.fps)
    const secs = totalSecs % 60
    const totalMins = Math.floor(totalSecs / 60)
    const mins = totalMins % 60
    const hours = Math.floor(totalMins / 60)
    return `${this._pad2(hours)}:${this._pad2(mins)}:${this._pad2(secs)}:${this._pad2(frames)}`
  },

  _pad2(n) {
    return n < 10 ? `0${n}` : `${n}`
  },

  /**
   * Get the current time and duration from the active audio engine.
   * Checks DawPreview, DjDeck, and AudioPlayer hooks.
   */
  _getActiveEngineTime() {
    // DAW mode: check DawPreview
    if (this.navTab === "daw") {
      return this._getDawTime()
    }

    // DJ mode: check DjDeck
    if (this.navTab === "dj") {
      return this._getDjTime()
    }

    // Library mode: check AudioPlayer
    return this._getAudioPlayerTime()
  },

  /**
   * Get time from DAW preview engine.
   */
  _getDawTime() {
    // Check the DAW transport bridge first (set by DawPreview hook)
    if (window.__dawTransport) {
      return {
        currentTime: window.__dawTransport.currentTime || 0,
        duration: window.__dawTransport.duration || 0,
      }
    }

    // Fallback: check window.__dawEditors for any wavesurfer instance
    const editors = window.__dawEditors || {}
    const firstEditor = Object.values(editors)[0]
    if (firstEditor && firstEditor.wavesurfer) {
      return {
        currentTime: firstEditor.wavesurfer.getCurrentTime() || 0,
        duration: firstEditor.wavesurfer.getDuration() || 0,
      }
    }
    return null
  },

  /**
   * Get time from DJ deck engine.
   */
  _getDjTime() {
    // DjDeck exposes transport state on window.__djTransport
    if (window.__djTransport) {
      return {
        currentTime: window.__djTransport.currentTime || 0,
        duration: window.__djTransport.duration || 0,
      }
    }
    return null
  },

  /**
   * Get time from the library AudioPlayer.
   */
  _getAudioPlayerTime() {
    const playerEl = document.querySelector("[phx-hook='AudioPlayer']")
    if (!playerEl) return null

    // AudioPlayer exposes time via the LiveView hook system
    if (window.__audioPlayerTransport) {
      return {
        currentTime: window.__audioPlayerTransport.currentTime || 0,
        duration: window.__audioPlayerTransport.duration || 0,
      }
    }
    return null
  },

  /**
   * Listen for transport_command events from the server and relay
   * them to the active audio engine.
   */
  _listenForTransportCommands() {
    this.handleEvent("transport_command", (payload) => {
      const { action } = payload

      switch (action) {
        case "play":
          this.isPlaying = true
          this._relayToEngine("play", payload)
          break
        case "pause":
          this.isPlaying = false
          this._relayToEngine("pause", payload)
          break
        case "stop":
          this.isPlaying = false
          this.currentTime = 0
          this._updateSmpteVisual(0)
          this._updateProgressVisual(0)
          this._relayToEngine("stop", payload)
          break
        case "seek":
          this.currentTime = payload.time || 0
          this._updateSmpteVisual(this.currentTime)
          if (this.duration > 0) {
            this._updateProgressVisual(
              (this.currentTime / this.duration) * 100
            )
          }
          this._relayToEngine("seek", payload)
          break
        case "rewind_start":
          this.currentTime = 0
          this._updateSmpteVisual(0)
          this._updateProgressVisual(0)
          this._relayToEngine("seek", { time: 0 })
          break
        case "volume":
          this._relayToEngine("volume", payload)
          break
        case "loop":
        case "loop_in":
        case "loop_out":
          this._relayToEngine(action, payload)
          break
        case "zoom":
          // Zoom is DAW-only, handled by DawEditor
          this._relayToEngine("zoom", payload)
          break
        case "record":
          // DAW-only recording
          this._relayToEngine("record", payload)
          break
      }
    })
  },

  /**
   * Relay a transport command to the active audio engine.
   */
  _relayToEngine(command, payload) {
    if (this.navTab === "daw") {
      this._relayToDaw(command, payload)
    } else if (this.navTab === "dj") {
      this._relayToDj(command, payload)
    } else {
      this._relayToAudioPlayer(command, payload)
    }
  },

  /**
   * Relay commands to the DAW preview engine.
   */
  _relayToDaw(command, payload) {
    // For DAW, we dispatch a custom event that DawPreview can listen to
    if (command === "play") {
      // Trigger the DawPreview toggle
      const previewEl = document.querySelector("[phx-hook='DawPreview']")
      if (previewEl && previewEl.__liveViewHookInstance) {
        previewEl.__liveViewHookInstance.pushEvent("toggle_preview", {})
      } else {
        // Fallback: use custom event dispatch
        window.dispatchEvent(
          new CustomEvent("sfa:transport", {
            detail: { command: "play", tab: "daw" },
          })
        )
      }
    } else if (command === "pause" || command === "stop") {
      window.dispatchEvent(
        new CustomEvent("sfa:transport", {
          detail: { command: command, tab: "daw" },
        })
      )
    } else if (command === "seek") {
      // Seek all DAW wavesurfer instances
      const editors = window.__dawEditors || {}
      Object.values(editors).forEach((editor) => {
        if (editor && editor.wavesurfer && editor.wavesurfer.getDuration() > 0) {
          const ratio = (payload.time || 0) / editor.wavesurfer.getDuration()
          editor.wavesurfer.seekTo(Math.min(1, Math.max(0, ratio)))
        }
      })
    }
  },

  /**
   * Relay commands to the DJ deck engine.
   */
  _relayToDj(command, payload) {
    window.dispatchEvent(
      new CustomEvent("sfa:transport", {
        detail: { command, tab: "dj", ...payload },
      })
    )
  },

  /**
   * Relay commands to the library AudioPlayer engine.
   */
  _relayToAudioPlayer(command, payload) {
    window.dispatchEvent(
      new CustomEvent("sfa:transport", {
        detail: { command, tab: "library", ...payload },
      })
    )
  },

  destroyed() {
    if (this._keyHandler) {
      document.removeEventListener("keydown", this._keyHandler)
    }
    if (this._rafId) {
      cancelAnimationFrame(this._rafId)
    }
    if (this._pollInterval) {
      clearInterval(this._pollInterval)
    }
  },
}

export default TransportBar
