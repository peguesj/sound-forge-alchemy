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
    this.audioContext = null
    this.stems = {}
    this.wavesurfer = null
    this.isPlaying = false
    this.startTime = 0
    this.pauseOffset = 0

    // Parse stem data from data attribute
    const stemData = JSON.parse(this.el.dataset.stems || "[]")

    if (stemData.length > 0) {
      this.initAudioContext(stemData)
    }

    // Handle LiveView events
    this.handleEvent("toggle_play", () => this.togglePlay())
    this.handleEvent("seek", ({ time }) => this.seek(time))
    this.handleEvent("set_volume", ({ level }) => this.setMasterVolume(level / 100))
    this.handleEvent("set_stem_volume", ({ stem, level }) => this.setStemVolume(stem, level / 100))
    this.handleEvent("mute_stem", ({ stem, muted }) => this.muteStem(stem, muted))
    this.handleEvent("solo_stem", ({ stem }) => this.soloStem(stem))

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

  async initAudioContext(stemData) {
    this.audioContext = new (window.AudioContext || window.webkitAudioContext)()
    this.masterGain = this.audioContext.createGain()
    this.masterGain.connect(this.audioContext.destination)
    this.masterGain.gain.value = 0.8

    // Load all stems in parallel
    const loadPromises = stemData.map(async (stem) => {
      try {
        const response = await fetch(stem.url)
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
      } catch (err) {
        console.warn(`Failed to load stem ${stem.type}:`, err)
      }
    })

    await Promise.all(loadPromises)

    // Report duration from the longest stem
    const durations = Object.values(this.stems).map(s => s.buffer.duration)
    const maxDuration = Math.max(...durations, 0)
    this.duration = maxDuration
    this.pushEvent("player_ready", { duration: maxDuration })

    // Initialize WaveSurfer waveform using the first stem (vocals preferred)
    this.initWaveform(stemData)
  },

  initWaveform(stemData) {
    const waveformEl = this.el.querySelector("[id^='waveform-']")
    if (!waveformEl) return

    // Prefer vocals stem for waveform, fallback to first available
    const vocalsUrl = stemData.find(s => s.type === "vocals")?.url
    const firstUrl = stemData[0]?.url
    const waveformUrl = vocalsUrl || firstUrl
    if (!waveformUrl) return

    this.wavesurfer = WaveSurfer.create({
      container: waveformEl,
      waveColor: "#6b7280",
      progressColor: "#a855f7",
      cursorColor: "#c084fc",
      height: 80,
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      responsive: true,
      interact: true,
      // Use MediaElement backend so WaveSurfer doesn't play audio itself
      // (we handle playback via Web Audio API for multi-stem)
      backend: "WebAudio",
      media: document.createElement("audio")
    })

    this.wavesurfer.load(waveformUrl)

    // Mute wavesurfer's own audio - we use our Web Audio API stems
    this.wavesurfer.setVolume(0)

    // Handle click-to-seek on the waveform
    this.wavesurfer.on("interaction", (newTime) => {
      const seekTime = newTime * this.duration
      this.seek(seekTime)
      this.pushEvent("time_update", { time: seekTime })
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
        } else {
          this.pushEvent("time_update", { time: currentTime })
          // Sync waveform cursor
          if (this.wavesurfer && this.duration > 0) {
            this.wavesurfer.seekTo(currentTime / this.duration)
          }
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

  destroyed() {
    if (this._keyHandler) {
      document.removeEventListener("keydown", this._keyHandler)
    }
    this.stopTimeUpdate()
    Object.values(this.stems).forEach(stem => {
      if (stem.source) {
        stem.source.stop()
      }
    })
    if (this.wavesurfer) {
      this.wavesurfer.destroy()
    }
    if (this.audioContext) {
      this.audioContext.close()
    }
  }
}

export default AudioPlayer
