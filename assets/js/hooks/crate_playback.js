/**
 * CratePlayback — Spotify 30-second preview audio hook for CrateDigger.
 *
 * Attached to a hidden sentinel element in crate_digger_live.ex.
 * Listens for:
 *   - crate_play_track  { spotify_id, preview_url } — play/swap preview
 *   - crate_stop_playback                            — stop and clear
 *
 * Pushes back to server:
 *   - crate_playback_started { spotify_id }
 *   - crate_playback_ended   { spotify_id }
 *   - crate_playback_error   { spotify_id, reason }
 *
 * DRTW L2: Uses native Audio API — no external library needed.
 */
const CratePlayback = {
  mounted() {
    this._audio = null
    this._currentId = null

    this.handleEvent('crate_play_track', ({ spotify_id, preview_url }) => {
      this._play(spotify_id, preview_url)
    })

    this.handleEvent('crate_stop_playback', () => {
      this._stop()
    })
  },

  destroyed() {
    this._stop()
  },

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  _safePush(event, payload) {
    try {
      if (this.__view && this.__view().isConnected()) {
        this.pushEvent(event, payload, () => {})
      }
    } catch (_) {}
  },

  _play(spotify_id, preview_url) {
    // Stop any currently playing track first
    this._stop()

    if (!preview_url) {
      this._safePush('crate_playback_error', { spotify_id, reason: 'no_preview' })
      return
    }

    this._currentId = spotify_id
    this._audio = new Audio(preview_url)
    this._audio.volume = 0.8

    this._audio.addEventListener('ended', () => {
      this._currentId = null
      this._safePush('crate_playback_ended', { spotify_id })
    }, { once: true })

    this._audio.play()
      .then(() => {
        this._safePush('crate_playback_started', { spotify_id })
      })
      .catch((err) => {
        this._currentId = null
        this._safePush('crate_playback_error', { spotify_id, reason: err.message })
      })
  },

  _stop() {
    if (this._audio) {
      this._audio.pause()
      this._audio.currentTime = 0
      this._audio = null
    }
    this._currentId = null
  }
}

export default CratePlayback
