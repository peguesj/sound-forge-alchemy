/**
 * PwaPermissions — Progressive Web App permission bootstrap hook.
 *
 * Attached to a hidden sentinel element in root.html.heex.
 * On mount:
 *  1. Reports Web MIDI availability to LiveView via pushEvent
 *  2. Prompts for MIDI access on first user gesture (deferred)
 *  3. Listens for phx:request-notification-permission to show the browser prompt
 *
 * DRTW L2: Uses native navigator.requestMIDIAccess() and Notification API.
 * No external library needed.
 */
const PwaPermissions = {
  mounted() {
    this._reportMidiAvailability()
    this._listenForNotificationRequest()
    this._requestMidiOnGesture()
  },

  destroyed() {
    if (this._midiAccess) {
      this._midiAccess.onstatechange = null
    }
  },

  // -------------------------------------------------------------------------
  // Web MIDI
  // -------------------------------------------------------------------------

  _reportMidiAvailability() {
    const available = !!navigator.requestMIDIAccess
    // Defer to next tick. Guard with isConnected() before push. Pass no-op
    // onReply so Phoenix chains .catch(()=>{}) internally, silencing any
    // Promise rejection if the view disconnects in the narrow window between
    // our check and pushHookEvent's own check.
    setTimeout(() => {
      try {
        if (this.__view && this.__view().isConnected()) {
          this.pushEvent('pwa_midi_available', { available }, () => {})
        }
      } catch (_) {}
    }, 0)
  },

  _requestMidiOnGesture() {
    if (!navigator.requestMIDIAccess) return

    const onGesture = () => {
      document.removeEventListener('click', onGesture, { once: true })
      document.removeEventListener('keydown', onGesture, { once: true })

      navigator.requestMIDIAccess({ sysex: false })
        .then((midiAccess) => {
          this._midiAccess = midiAccess
          this._reportMidiDevices(midiAccess)

          midiAccess.onstatechange = () => {
            this._reportMidiDevices(midiAccess)
          }
        })
        .catch(() => {
          // User denied MIDI access — not fatal
          if (this.__view && this.__view().isConnected()) {
            this.pushEvent('pwa_midi_permission', { granted: false }, () => {})
          }
        })
    }

    document.addEventListener('click', onGesture, { once: true })
    document.addEventListener('keydown', onGesture, { once: true })
  },

  _reportMidiDevices(midiAccess) {
    const inputs = []
    midiAccess.inputs.forEach((input) => {
      inputs.push({ id: input.id, name: input.name, state: input.state })
    })
    const outputs = []
    midiAccess.outputs.forEach((output) => {
      outputs.push({ id: output.id, name: output.name, state: output.state })
    })

    // Defer to next tick. Guard with isConnected() before push — same rationale.
    // Pass no-op onReply to silence any race-condition Promise rejection.
    setTimeout(() => {
      try {
        if (this.__view && this.__view().isConnected()) {
          this.pushEvent('pwa_midi_devices', { inputs, outputs, granted: true }, () => {})
        }
      } catch (_) {}
    }, 0)
  },

  // -------------------------------------------------------------------------
  // Push Notifications
  // -------------------------------------------------------------------------

  _listenForNotificationRequest() {
    window.addEventListener('phx:request-notification-permission', () => {
      this._requestNotificationPermission()
    })
  },

  async _requestNotificationPermission() {
    const safePush = (event, payload) => {
      try {
        if (this.__view && this.__view().isConnected()) {
          this.pushEvent(event, payload, () => {})
        }
      } catch (_) {}
    }
    if (!('Notification' in window)) {
      safePush('pwa_notification_permission', { granted: false, reason: 'unsupported' })
      return
    }

    if (Notification.permission === 'granted') {
      safePush('pwa_notification_permission', { granted: true, reason: 'already_granted' })
      this._subscribeToServiceWorkerPush()
      return
    }

    if (Notification.permission === 'denied') {
      safePush('pwa_notification_permission', { granted: false, reason: 'denied' })
      return
    }

    try {
      const permission = await Notification.requestPermission()
      const granted = permission === 'granted'
      safePush('pwa_notification_permission', { granted, reason: permission })

      if (granted) {
        this._subscribeToServiceWorkerPush()
      }
    } catch {
      safePush('pwa_notification_permission', { granted: false, reason: 'error' })
    }
  },

  async _subscribeToServiceWorkerPush() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) return

    const safePush = (event, payload) => {
      try {
        if (this.__view && this.__view().isConnected()) {
          this.pushEvent(event, payload, () => {})
        }
      } catch (_) {}
    }

    try {
      const registration = await navigator.serviceWorker.ready

      // Check if already subscribed
      const existing = await registration.pushManager.getSubscription()
      if (existing) {
        safePush('pwa_push_subscription', {
          endpoint: existing.endpoint,
          keys: {
            p256dh: btoa(String.fromCharCode(...new Uint8Array(existing.getKey('p256dh')))),
            auth: btoa(String.fromCharCode(...new Uint8Array(existing.getKey('auth'))))
          }
        })
        return
      }

      // Fetch VAPID public key from server
      const res = await fetch('/api/push/vapid-public-key')
      if (!res.ok) return

      const { vapid_public_key } = await res.json()
      if (!vapid_public_key) return

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this._urlBase64ToUint8Array(vapid_public_key)
      })

      safePush('pwa_push_subscription', {
        endpoint: subscription.endpoint,
        keys: {
          p256dh: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey('p256dh')))),
          auth: btoa(String.fromCharCode(...new Uint8Array(subscription.getKey('auth'))))
        }
      })
    } catch {
      // Push subscription failed — non-fatal
    }
  },

  _urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
    const rawData = atob(base64)
    return Uint8Array.from([...rawData].map((char) => char.charCodeAt(0)))
  }
}

export default PwaPermissions
