/**
 * SamplePreview Hook
 *
 * Provides in-browser audio preview for sample files.
 * Attach to a button element with data-file-path set to the sample's file path.
 *
 * Usage:
 *   <button phx-hook="SamplePreview" id="preview-{id}" data-file-path="/files/samples/kick.wav">▶</button>
 */

const SamplePreview = {
  mounted() {
    this._audioCtx = null
    this._source = null
    this._playing = false

    this.el.addEventListener("click", () => this.togglePreview())
  },

  destroyed() {
    this._stopPlayback()
    if (this._audioCtx) {
      this._audioCtx.close()
      this._audioCtx = null
    }
  },

  async togglePreview() {
    if (this._playing) {
      this._stopPlayback()
      this._setIcon("▶")
      return
    }

    const filePath = this.el.dataset.filePath
    if (!filePath) return

    this._setIcon("⏳")

    try {
      if (!this._audioCtx) {
        this._audioCtx = new (window.AudioContext || window.webkitAudioContext)()
      }

      // Resume context if suspended (browser autoplay policy)
      if (this._audioCtx.state === "suspended") {
        await this._audioCtx.resume()
      }

      const response = await fetch(filePath)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const arrayBuffer = await response.arrayBuffer()
      const audioBuffer = await this._audioCtx.decodeAudioData(arrayBuffer)

      this._source = this._audioCtx.createBufferSource()
      this._source.buffer = audioBuffer
      this._source.connect(this._audioCtx.destination)

      this._source.onended = () => {
        this._playing = false
        this._source = null
        this._setIcon("▶")
      }

      this._source.start(0)
      this._playing = true
      this._setIcon("⏹")
    } catch (err) {
      console.error("[SamplePreview] Error:", err)
      this._playing = false
      this._setIcon("▶")
    }
  },

  _stopPlayback() {
    if (this._source) {
      try {
        this._source.stop()
      } catch (_) {
        // Already stopped
      }
      this._source = null
    }
    this._playing = false
  },

  _setIcon(icon) {
    this.el.textContent = icon
  }
}

export default SamplePreview
