/**
 * DawPreview Hook - Coordinated preview playback across all DAW stems
 *
 * Attached to the page-level container div. Listens for "daw_preview" events
 * from the server, creates a single AudioContext, and schedules all stems'
 * audio buffers with edit operations applied (crop, gain, fade in/out).
 *
 * Each per-stem DawEditor hook registers itself on window.__dawEditors
 * keyed by stemId, exposing its wavesurfer instance. This hook reads the
 * decoded AudioBuffer from each wavesurfer via getDecodedData().
 *
 * WaveSurfer cursors across all stems are synchronized to track the
 * current playback position via a 50ms interval timer.
 */

const DawPreview = {
  mounted() {
    this._previewContext = null
    this._previewSources = []
    this._previewPlaying = false
    this._previewStartTime = 0
    this._previewCursorInterval = null

    this.handleEvent("daw_preview", (payload) => this._handlePreview(payload))

    // Initialize transport bridge for DAW
    window.__dawTransport = { currentTime: 0, duration: 0, playing: false }

    // Listen for transport commands from TransportBar
    this._transportHandler = (e) => {
      const { command, tab } = e.detail || {}
      if (tab !== "daw") return

      switch (command) {
        case "play":
          if (!this._previewPlaying) {
            this.pushEvent("toggle_preview", {})
          }
          break
        case "pause":
        case "stop":
          if (this._previewPlaying) {
            this.pushEvent("toggle_preview", {})
          }
          if (command === "stop") {
            // Reset cursors to beginning
            const editors = window.__dawEditors || {}
            Object.values(editors).forEach((editor) => {
              if (editor && editor.wavesurfer) editor.wavesurfer.seekTo(0)
            })
            window.__dawTransport = { currentTime: 0, duration: 0, playing: false }
          }
          break
      }
    }
    window.addEventListener("sfa:transport", this._transportHandler)

    // Spacebar toggles play/pause (ignore if focus is in an input/textarea)
    this._keyHandler = (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return
      if (e.key === " ") {
        e.preventDefault()
        this.pushEvent("toggle_preview", {})
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  },

  _handlePreview({ playing, operations }) {
    if (playing) {
      this._startPreview(operations)
    } else {
      this._stopPreview()
    }
  },

  _startPreview(operations) {
    this._stopPreview()

    const editors = window.__dawEditors || {}
    const stemIds = Object.keys(editors)
    if (stemIds.length === 0) return

    let ctx
    try {
      ctx = new (window.AudioContext || window.webkitAudioContext)()
    } catch (_e) {
      console.error("DawPreview: AudioContext not available")
      return
    }
    this._previewContext = ctx
    this._previewPlaying = true
    this._previewStartTime = ctx.currentTime

    stemIds.forEach((stemId) => {
      const editor = editors[stemId]
      if (!editor || !editor.wavesurfer) return

      const buffer = editor.wavesurfer.getDecodedData()
      if (!buffer) return

      const ops = operations ? (operations[stemId] || []) : []

      const cropOp = ops.find((o) => o.type === "crop")
      const gainOps = ops.filter((o) => o.type === "gain")
      const fadeInOp = ops.find((o) => o.type === "fade_in")
      const fadeOutOp = ops.find((o) => o.type === "fade_out")

      let startTime = 0
      let endTime = buffer.duration

      if (cropOp && cropOp.params) {
        startTime = (cropOp.params.start_ms || 0) / 1000
        endTime = (cropOp.params.end_ms || buffer.duration * 1000) / 1000
      }

      const duration = endTime - startTime

      const source = ctx.createBufferSource()
      source.buffer = buffer

      const gainNode = ctx.createGain()
      let baseGain = 1.0

      gainOps.forEach((op) => {
        if (op.params && op.params.level != null) {
          baseGain = op.params.level
        }
      })
      gainNode.gain.value = baseGain

      if (fadeInOp && fadeInOp.params) {
        const fadeDuration = (fadeInOp.params.duration_ms || 1000) / 1000
        gainNode.gain.setValueAtTime(0, ctx.currentTime)
        gainNode.gain.linearRampToValueAtTime(
          baseGain,
          ctx.currentTime + fadeDuration
        )
      }

      if (fadeOutOp && fadeOutOp.params) {
        const fadeDuration = (fadeOutOp.params.duration_ms || 1000) / 1000
        const fadeStart = duration - fadeDuration
        if (fadeStart > 0) {
          gainNode.gain.setValueAtTime(baseGain, ctx.currentTime + fadeStart)
          gainNode.gain.linearRampToValueAtTime(0, ctx.currentTime + duration)
        }
      }

      source.connect(gainNode)
      gainNode.connect(ctx.destination)
      source.start(0, startTime, duration)

      this._previewSources.push({ source, gainNode, duration, stemId })
    })

    this._startPreviewCursor()
  },

  _stopPreview() {
    this._previewPlaying = false

    this._previewSources.forEach(({ source }) => {
      try {
        source.stop()
      } catch (_e) {
        // source may already have stopped
      }
    })
    this._previewSources = []

    if (this._previewContext) {
      this._previewContext.close().catch(() => {})
      this._previewContext = null
    }

    this._stopPreviewCursor()

    // Update transport bridge
    if (window.__dawTransport) {
      window.__dawTransport.playing = false
    }

    // Reset all wavesurfer cursors to the beginning
    const editors = window.__dawEditors || {}
    Object.values(editors).forEach((editor) => {
      if (editor && editor.wavesurfer) {
        editor.wavesurfer.seekTo(0)
      }
    })
  },

  _startPreviewCursor() {
    this._previewCursorInterval = setInterval(() => {
      if (!this._previewPlaying || !this._previewContext) {
        this._stopPreviewCursor()
        return
      }

      const elapsed = this._previewContext.currentTime - this._previewStartTime
      let maxDuration = 0

      const editors = window.__dawEditors || {}
      Object.values(editors).forEach((editor) => {
        if (!editor || !editor.wavesurfer) return

        const buffer = editor.wavesurfer.getDecodedData()
        if (buffer) {
          maxDuration = Math.max(maxDuration, buffer.duration)
          const ratio = Math.min(elapsed / buffer.duration, 1)
          editor.wavesurfer.seekTo(ratio)
        }
      })

      // Update transport bridge for TransportBar
      window.__dawTransport = {
        currentTime: elapsed,
        duration: maxDuration,
        playing: true,
      }

      if (elapsed >= maxDuration && maxDuration > 0) {
        this._stopPreview()
        this.pushEvent("stop_preview", {})
      }
    }, 50)
  },

  _stopPreviewCursor() {
    if (this._previewCursorInterval) {
      clearInterval(this._previewCursorInterval)
      this._previewCursorInterval = null
    }
  },

  destroyed() {
    if (this._keyHandler) {
      document.removeEventListener("keydown", this._keyHandler)
    }
    if (this._transportHandler) {
      window.removeEventListener("sfa:transport", this._transportHandler)
    }
    delete window.__dawTransport
    this._stopPreview()
  },
}

export default DawPreview
