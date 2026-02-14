/**
 * SpotifyPlayer Hook - Spotify Web Playback SDK integration for Phoenix LiveView
 *
 * Initializes a Spotify Web Playback SDK player instance, manages playback
 * (play, pause, seek), and syncs playback state back to the LiveView process.
 * Requires a Spotify Premium account and a valid OAuth access token.
 */
const SpotifyPlayer = {
  mounted() {
    this.player = null
    this.deviceId = null
    this.token = null
    this.sdkReady = false
    this.pendingInit = false
    this.pendingPlay = null // Queue a play request until device is ready

    // Check if the SDK script is already loaded
    if (window.Spotify) {
      this.sdkReady = true
    } else {
      // The SDK calls this global callback when it finishes loading
      const existingCallback = window.onSpotifyWebPlaybackSDKReady
      window.onSpotifyWebPlaybackSDKReady = () => {
        if (existingCallback) existingCallback()
        this.sdkReady = true
        if (this.pendingInit) {
          this.initPlayer()
          this.pendingInit = false
        }
      }
    }

    // Listen for token delivery from the server
    this.handleEvent("spotify_token", ({ token }) => {
      const tokenChanged = this.token !== token
      this.token = token

      if (!this.player || !this.deviceId) {
        // No player yet or not connected - initialize
        if (this.sdkReady) {
          this.initPlayer()
        } else {
          this.pendingInit = true
        }
      } else if (tokenChanged) {
        // Player exists and connected - just update the token for API calls.
        // Don't re-init the player, as that would drop the device registration.
        console.log("[SpotifyPlayer] Token refreshed, keeping existing connection")
      }
    })

    // Playback control events from the server
    this.handleEvent("spotify_play", ({ uri }) => this.play(uri))
    this.handleEvent("spotify_pause", () => this.pause())
    this.handleEvent("spotify_resume", () => this.resume())
    this.handleEvent("spotify_seek", ({ position_ms }) => this.seek(position_ms))
  },

  initPlayer() {
    if (this.player) {
      this.player.disconnect()
      this.deviceId = null
    }

    if (!this.token) {
      console.warn("[SpotifyPlayer] No access token available, skipping init")
      return
    }

    const self = this

    this.player = new Spotify.Player({
      name: "Sound Forge Alchemy",
      getOAuthToken: (cb) => cb(self.token),
      volume: 0.8
    })

    // Ready - device is available for playback
    this.player.addListener("ready", ({ device_id }) => {
      self.deviceId = device_id
      console.log("[SpotifyPlayer] Ready with device ID:", device_id)
      self.pushEvent("spotify_player_ready", { device_id })

      // If a play request was queued while waiting for device, execute it now
      if (self.pendingPlay) {
        const uri = self.pendingPlay
        self.pendingPlay = null
        self.play(uri)
      }
    })

    // Not ready - device has gone offline
    this.player.addListener("not_ready", ({ device_id }) => {
      console.warn("[SpotifyPlayer] Device went offline:", device_id)
      self.deviceId = null
      self.pushEvent("spotify_player_not_ready", { device_id })
    })

    // Playback state changed - sync back to LiveView
    this.player.addListener("player_state_changed", (state) => {
      if (!state) return

      const currentTrack = state.track_window.current_track
      self.pushEvent("spotify_playback_state", {
        playing: !state.paused,
        position_ms: state.position,
        duration_ms: state.duration,
        track_name: currentTrack?.name || null,
        artist_name: currentTrack?.artists?.map((a) => a.name).join(", ") || null,
        album_art_url: currentTrack?.album?.images?.[0]?.url || null,
        track_uri: currentTrack?.uri || null
      })
    })

    // Error handlers
    this.player.addListener("initialization_error", ({ message }) => {
      console.error("[SpotifyPlayer] Initialization error:", message)
      self.pushEvent("spotify_error", { type: "initialization", message })
    })

    this.player.addListener("authentication_error", ({ message }) => {
      console.error("[SpotifyPlayer] Authentication error:", message)
      self.pushEvent("spotify_error", { type: "authentication", message })
    })

    this.player.addListener("account_error", ({ message }) => {
      console.error("[SpotifyPlayer] Account error (Premium required):", message)
      self.pushEvent("spotify_error", { type: "account", message })
    })

    this.player.addListener("playback_error", ({ message }) => {
      console.error("[SpotifyPlayer] Playback error:", message)
      self.pushEvent("spotify_error", { type: "playback", message })
    })

    this.player.connect().then((success) => {
      if (!success) {
        console.error("[SpotifyPlayer] Failed to connect")
        self.pushEvent("spotify_error", {
          type: "connection",
          message: "Failed to connect to Spotify"
        })
      }
    })
  },

  /**
   * Start playback of a Spotify URI on this device.
   * Uses the Spotify Web API directly since the SDK player
   * does not expose a play-by-URI method.
   */
  async play(spotifyUri) {
    if (!this.token) {
      console.warn("[SpotifyPlayer] Cannot play: no token")
      return
    }

    // If the device isn't ready yet, queue the play request
    if (!this.deviceId) {
      console.log("[SpotifyPlayer] Device not ready, queuing play request")
      this.pendingPlay = spotifyUri
      return
    }

    try {
      const response = await fetch(
        `https://api.spotify.com/v1/me/player/play?device_id=${this.deviceId}`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.token}`
          },
          body: JSON.stringify({ uris: [spotifyUri] })
        }
      )

      if (!response.ok) {
        const error = await response.json().catch(() => ({}))
        console.error("[SpotifyPlayer] Play API error:", response.status, error)
        this.pushEvent("spotify_error", {
          type: "playback",
          message: error?.error?.message || `HTTP ${response.status}`
        })
      }
    } catch (err) {
      console.error("[SpotifyPlayer] Play request failed:", err)
      this.pushEvent("spotify_error", {
        type: "playback",
        message: err.message || "Network error"
      })
    }
  },

  pause() {
    if (this.player) {
      this.player.pause().catch((err) => {
        console.warn("[SpotifyPlayer] Pause failed:", err)
      })
    }
  },

  resume() {
    if (this.player) {
      this.player.resume().catch((err) => {
        console.warn("[SpotifyPlayer] Resume failed:", err)
      })
    }
  },

  seek(positionMs) {
    if (this.player) {
      this.player.seek(positionMs).catch((err) => {
        console.warn("[SpotifyPlayer] Seek failed:", err)
      })
    }
  },

  destroyed() {
    if (this.player) {
      this.player.disconnect()
      this.player = null
    }
    this.deviceId = null
    this.token = null
    this.pendingPlay = null
  }
}

export default SpotifyPlayer
