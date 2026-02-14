/**
 * ShiftSelect Hook - Enables shift+click range selection for track checkboxes.
 *
 * Tracks the last-clicked checkbox. On shift+click, sends a
 * "shift_select_range" event with {from_id, to_id} to the server.
 */
const ShiftSelect = {
  mounted() {
    this.lastChecked = null

    this.el.addEventListener("click", (e) => {
      const checkbox = e.target.closest("[data-select-id]")
      if (!checkbox) return

      if (e.shiftKey && this.lastChecked) {
        this.pushEvent("shift_select_range", {
          from_id: this.lastChecked,
          to_id: checkbox.dataset.selectId
        })
      }

      this.lastChecked = checkbox.dataset.selectId
    })
  }
}

export default ShiftSelect
