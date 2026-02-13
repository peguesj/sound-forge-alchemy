/**
 * AudioPlayer Hook - Multi-stem Web Audio API player
 *
 * Loads multiple audio stems and plays them simultaneously with
 * independent volume control per stem, solo, and mute.
 */
const AudioPlayer = {
  mounted() {
    this.audioContext = null
    this.stems = {}
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
          muted: false
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
        // Solo mode: mute all except soloed stem
        const volume = type === stemType ? stem.volume : 0
        stem.gainNode.gain.setValueAtTime(volume, this.audioContext.currentTime)
      } else {
        // Unsolo: restore volumes based on mute state
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
        } else {
          this.pushEvent("time_update", { time: currentTime })
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
    this.stopTimeUpdate()
    Object.values(this.stems).forEach(stem => {
      if (stem.source) {
        stem.source.stop()
      }
    })
    if (this.audioContext) {
      this.audioContext.close()
    }
  }
}

export default AudioPlayer
