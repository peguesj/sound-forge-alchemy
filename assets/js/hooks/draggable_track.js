/**
 * DraggableTrack Hook — sets up drag data for Splice track cards
 * so they can be dropped onto PadDropTarget pads in the loop deck.
 */
const DraggableTrack = {
  mounted() {
    this.el.addEventListener("dragstart", this.onDragStart.bind(this))
    this.el.addEventListener("dragend", this.onDragEnd.bind(this))
  },

  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart.bind(this))
    this.el.removeEventListener("dragend", this.onDragEnd.bind(this))
  },

  onDragStart(e) {
    const trackId = this.el.dataset.trackId
    if (!trackId) return

    e.dataTransfer.effectAllowed = "copy"
    e.dataTransfer.setData("text/track-id", trackId)
    e.dataTransfer.setData("text/plain", trackId)
    this.el.classList.add("opacity-60", "scale-95")
  },

  onDragEnd() {
    this.el.classList.remove("opacity-60", "scale-95")
  }
}

export default DraggableTrack
