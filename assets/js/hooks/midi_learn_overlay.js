/**
 * MidiLearnOverlay Hook
 *
 * When the overlay becomes active (`data-active="true"`), adds click listeners
 * to every element in the page that has `data-midi-learn-id` attribute.
 * Clicking such an element pushes `select_control` to the LiveComponent.
 *
 * Provides visual feedback:
 * - `midi-learn-highlight` class on all learnable controls when active
 * - `midi-learn-target` class on the clicked control while waiting for MIDI
 * - `midi-learn-done` flash on assignment
 */
const MidiLearnOverlay = {
  mounted() {
    this._active = this.el.dataset.active === "true"
    this._clickHandlers = new Map()

    if (this._active) this._activateLearn()

    this.handleEvent("midi_learn_waiting", ({ control_id }) => {
      this._clearAllTargets()
      const el = document.querySelector(`[data-midi-learn-id="${control_id}"]`)
      if (el) el.classList.add("midi-learn-target", "animate-pulse")
    })

    this.handleEvent("midi_learn_assigned", ({ control_id, device, success }) => {
      this._clearAllTargets()
      const el = document.querySelector(`[data-midi-learn-id="${control_id}"]`)
      if (el) {
        el.classList.add(success ? "midi-learn-done" : "midi-learn-error")
        setTimeout(() => {
          el.classList.remove("midi-learn-done", "midi-learn-error")
        }, 1500)
      }
    })

    this.handleEvent("midi_learn_cancelled", () => {
      this._clearAllTargets()
    })
  },

  updated() {
    const nowActive = this.el.dataset.active === "true"
    if (nowActive && !this._active) {
      this._activateLearn()
    } else if (!nowActive && this._active) {
      this._deactivateLearn()
    }
    this._active = nowActive
  },

  destroyed() {
    this._deactivateLearn()
  },

  _activateLearn() {
    const controls = document.querySelectorAll("[data-midi-learn-id]")
    controls.forEach(el => {
      el.classList.add("midi-learn-highlight")

      const handler = (e) => {
        e.stopPropagation()
        const id = el.dataset.midiLearnId
        const label = el.dataset.midiLearnLabel || id
        this.pushEventTo(this.el, "select_control", { id, label })
      }

      this._clickHandlers.set(el, handler)
      el.addEventListener("click", handler, { capture: true })
    })
  },

  _deactivateLearn() {
    this._clickHandlers.forEach((handler, el) => {
      el.removeEventListener("click", handler, { capture: true })
      el.classList.remove("midi-learn-highlight", "midi-learn-target", "midi-learn-done", "midi-learn-error")
    })
    this._clickHandlers.clear()
  },

  _clearAllTargets() {
    document.querySelectorAll(".midi-learn-target").forEach(el => {
      el.classList.remove("midi-learn-target", "animate-pulse")
    })
  }
}

export default MidiLearnOverlay
