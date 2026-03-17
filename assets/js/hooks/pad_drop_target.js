/**
 * PadDropTarget Hook — allows Splice track cards to be dragged onto loop deck pads
 *
 * Track cards in the library must have:
 *   draggable="true"
 *   data-track-id="{id}"
 *   data-source="splice"  (or any source)
 *
 * Pads with this hook push "drop_splice_on_pad" event when a valid track is dropped.
 */
const PadDropTarget = {
  mounted() {
    this.el.addEventListener("dragover", this.onDragOver.bind(this))
    this.el.addEventListener("dragleave", this.onDragLeave.bind(this))
    this.el.addEventListener("drop", this.onDrop.bind(this))
  },

  destroyed() {
    this.el.removeEventListener("dragover", this.onDragOver.bind(this))
    this.el.removeEventListener("dragleave", this.onDragLeave.bind(this))
    this.el.removeEventListener("drop", this.onDrop.bind(this))
  },

  onDragOver(e) {
    const trackId = e.dataTransfer?.getData("text/track-id")
    if (trackId || e.dataTransfer?.types.includes("text/track-id")) {
      e.preventDefault()
      e.dataTransfer.dropEffect = "copy"
      this.el.classList.add("ring-2", "ring-cyan-400", "ring-offset-1")
    }
  },

  onDragLeave() {
    this.el.classList.remove("ring-2", "ring-cyan-400", "ring-offset-1")
  },

  onDrop(e) {
    this.el.classList.remove("ring-2", "ring-cyan-400", "ring-offset-1")
    const trackId = e.dataTransfer?.getData("text/track-id")
    if (!trackId) return

    e.preventDefault()

    const deck = this.el.dataset.deck
    const pad = this.el.dataset.pad

    this.pushEvent("drop_splice_on_pad", {
      deck: deck,
      pad: pad,
      track_id: trackId
    })
  }
}

export default PadDropTarget
