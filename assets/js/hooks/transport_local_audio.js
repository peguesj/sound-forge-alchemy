/**
 * TransportLocalAudio Hook
 *
 * Provides an inline HTML5 Audio player for the transport bar.
 * Bridges with the existing TransportBar hook via:
 *   - window.__audioPlayerTransport (polled by TransportBar for SMPTE display)
 *   - window "sfa:transport" custom events (emitted by TransportBar for commands)
 *
 * Server events received:
 *   load_local_track: { url }  – load (and optionally auto-play) a track URL
 */
const TransportLocalAudio = {
  mounted() {
    this.audio = new Audio()
    this.audio.preload = "auto"
    this._loaded = false

    const self = this

    // Keep window.__audioPlayerTransport in sync (TransportBar reads this)
    this.audio.addEventListener("timeupdate", () => {
      window.__audioPlayerTransport = {
        currentTime: self.audio.currentTime,
        duration: self.audio.duration || 0,
        playing: !self.audio.paused
      }
    })

    this.audio.addEventListener("loadedmetadata", () => {
      self._loaded = true
      window.__audioPlayerTransport = {
        currentTime: 0,
        duration: self.audio.duration || 0,
        playing: false
      }
      self.pushEvent("transport_duration_updated", { duration: self.audio.duration || 0 })
    })

    this.audio.addEventListener("ended", () => {
      window.__audioPlayerTransport = {
        currentTime: 0,
        duration: self.audio.duration || 0,
        playing: false
      }
      self.pushEvent("transport_ended", {})
    })

    this.audio.addEventListener("error", () => {
      console.warn("[TransportLocalAudio] Playback error for:", self.audio.src)
    })

    // Relay commands from TransportBar hook (dispatched as window "sfa:transport" events)
    this._onTransport = (e) => {
      const { action, value } = e.detail || {}
      switch (action) {
        case "play":
          self.audio.play().catch((err) =>
            console.warn("[TransportLocalAudio] play() blocked:", err)
          )
          break
        case "pause":
          self.audio.pause()
          break
        case "stop":
          self.audio.pause()
          self.audio.currentTime = 0
          break
        case "rewind_start":
          self.audio.currentTime = 0
          break
        case "seek":
          if (typeof value === "number") self.audio.currentTime = value
          break
        case "volume":
          if (typeof value === "number") self.audio.volume = Math.max(0, Math.min(1, value / 100))
          break
      }
    }
    window.addEventListener("sfa:transport", this._onTransport)

    // Load a new track URL from the server
    this.handleEvent("load_local_track", ({ url }) => {
      if (!url) return
      const wasPlaying = !self.audio.paused && self._loaded
      self._loaded = false
      self.audio.pause()
      self.audio.src = url
      self.audio.load()
      if (wasPlaying) {
        // Resume playback on new src if it was already playing
        self.audio.addEventListener(
          "canplay",
          () => self.audio.play().catch(() => {}),
          { once: true }
        )
      }
    })
  },

  destroyed() {
    if (this.audio) {
      this.audio.pause()
      this.audio.src = ""
      this.audio = null
    }
    window.removeEventListener("sfa:transport", this._onTransport)
    window.__audioPlayerTransport = null
  }
}

export default TransportLocalAudio
