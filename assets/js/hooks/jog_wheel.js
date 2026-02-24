/**
 * JogWheel Hook - Rotational tracking for virtual DJ jog wheels.
 *
 * Tracks pointer drag rotation around the wheel center and emits
 * scratch/nudge events to the server. The center button supports
 * press-and-hold for cue functionality.
 *
 * Events pushed to server:
 *   - jog_scratch: { deck, delta } - rotation delta in degrees
 *   - jog_cue_press: { deck } - center button pressed
 *   - jog_cue_release: { deck } - center button released
 */
const JogWheel = {
  mounted() {
    this.deck = parseInt(this.el.dataset.deck)
    this.rotation = 0
    this.isDragging = false
    this.lastAngle = null
    this.indicator = this.el.querySelector(".jog-indicator")
    this.cueHeld = false

    const svg = this.el.querySelector("svg")

    svg.addEventListener("pointerdown", (e) => this._onPointerDown(e))
    this._onPointerMoveBound = (e) => this._onPointerMove(e)
    this._onPointerUpBound = (e) => this._onPointerUp(e)
    document.addEventListener("pointermove", this._onPointerMoveBound)
    document.addEventListener("pointerup", this._onPointerUpBound)

    // Prevent default touch behavior for smooth interaction
    svg.addEventListener("touchstart", (e) => e.preventDefault(), { passive: false })
  },

  _getAngle(e) {
    const rect = this.el.getBoundingClientRect()
    const cx = rect.left + rect.width / 2
    const cy = rect.top + rect.height / 2
    return Math.atan2(e.clientY - cy, e.clientX - cx) * (180 / Math.PI)
  },

  _isCenter(e) {
    const rect = this.el.getBoundingClientRect()
    const cx = rect.left + rect.width / 2
    const cy = rect.top + rect.height / 2
    const dist = Math.sqrt((e.clientX - cx) ** 2 + (e.clientY - cy) ** 2)
    const radius = rect.width / 2
    return dist < radius * 0.25
  },

  _onPointerDown(e) {
    if (this._isCenter(e)) {
      this.cueHeld = true
      this.pushEvent("jog_cue_press", { deck: this.deck })
      return
    }
    this.isDragging = true
    this.lastAngle = this._getAngle(e)
    this.el.setPointerCapture(e.pointerId)
  },

  _onPointerMove(e) {
    if (!this.isDragging) return
    const angle = this._getAngle(e)
    if (this.lastAngle !== null) {
      let delta = angle - this.lastAngle
      // Normalize delta to handle the -180/180 boundary
      if (delta > 180) delta -= 360
      if (delta < -180) delta += 360

      this.rotation += delta
      if (this.indicator) {
        this.indicator.setAttribute("transform", `rotate(${this.rotation}, 80, 80)`)
      }

      // Only send events for meaningful rotations
      if (Math.abs(delta) > 0.5) {
        this.pushEvent("jog_scratch", { deck: this.deck, delta: delta })
      }
    }
    this.lastAngle = angle
  },

  _onPointerUp(_e) {
    if (this.cueHeld) {
      this.cueHeld = false
      this.pushEvent("jog_cue_release", { deck: this.deck })
    }
    this.isDragging = false
    this.lastAngle = null
  },

  destroyed() {
    document.removeEventListener("pointermove", this._onPointerMoveBound)
    document.removeEventListener("pointerup", this._onPointerUpBound)
  }
}

export default JogWheel
