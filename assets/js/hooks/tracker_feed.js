/**
 * TrackerFeed — LiveView hook wrapping an EventSource on the SFA realtime
 * tracker (or chat) SSE endpoint, with exponential backoff reconnect.
 *
 * Usage:
 *   <div phx-hook="TrackerFeed" id="tracker-feed"
 *        data-url="/api/tracker/events"></div>
 *
 * Each SSE payload is pushed to the LiveView as a "tracker_event" event and
 * dispatched on the element as a "tracker:event" CustomEvent for other JS.
 */
const BASE_DELAY_MS = 1000
const MAX_DELAY_MS = 30000

const TrackerFeed = {
  mounted() {
    this.url = this.el.dataset.url || "/api/tracker/events"
    this.attempt = 0
    this.closed = false
    this.connect()
  },

  connect() {
    if (this.closed) return
    this.source = new EventSource(this.url)

    this.source.onopen = () => {
      this.attempt = 0
      this.setStatus("online")
    }

    this.source.onmessage = (event) => {
      let payload
      try {
        payload = JSON.parse(event.data)
      } catch (_e) {
        return
      }
      this.pushEvent("tracker_event", payload)
      this.el.dispatchEvent(
        new CustomEvent("tracker:event", {detail: payload, bubbles: true})
      )
    }

    this.source.onerror = () => {
      // Improve on fail-to-offline: back off and retry instead of giving up.
      this.source.close()
      this.setStatus("reconnecting")
      const delay = Math.min(BASE_DELAY_MS * 2 ** this.attempt, MAX_DELAY_MS)
      const jitter = Math.random() * 0.3 * delay
      this.attempt += 1
      this.retryTimer = setTimeout(() => this.connect(), delay + jitter)
    }
  },

  setStatus(status) {
    this.el.dataset.trackerStatus = status
    this.pushEvent("tracker_status", {status})
  },

  destroyed() {
    this.closed = true
    if (this.retryTimer) clearTimeout(this.retryTimer)
    if (this.source) this.source.close()
  },
}

export default TrackerFeed
