import WaveSurfer from "wavesurfer.js"

const AudioPlayer = {
  mounted() {
    const audioUrl = this.el.dataset.audioUrl
    const waveformId = this.el.querySelector("[id^='waveform-']").id

    this.wavesurfer = WaveSurfer.create({
      container: `#${waveformId}`,
      waveColor: "#6b7280",
      progressColor: "#a855f7",
      cursorColor: "#c084fc",
      height: 64,
      barWidth: 2,
      barGap: 1,
      responsive: true,
      backend: "WebAudio"
    })

    if (audioUrl) {
      this.wavesurfer.load(audioUrl)
    }

    this.wavesurfer.on("ready", () => {
      this.pushEvent("player_ready", { duration: this.wavesurfer.getDuration() })
    })

    this.wavesurfer.on("audioprocess", () => {
      this.pushEvent("time_update", { time: this.wavesurfer.getCurrentTime() })
    })

    this.handleEvent("toggle_play", () => {
      this.wavesurfer.playPause()
    })

    this.handleEvent("seek", ({ time }) => {
      this.wavesurfer.seekTo(time / this.wavesurfer.getDuration())
    })

    this.handleEvent("set_volume", ({ level }) => {
      this.wavesurfer.setVolume(level / 100)
    })
  },

  destroyed() {
    if (this.wavesurfer) {
      this.wavesurfer.destroy()
    }
  }
}

export default AudioPlayer
