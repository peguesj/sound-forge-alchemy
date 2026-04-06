/**
 * MidiMonitorScroll Hook — auto-scroll for MIDI monitor event list
 *
 * When tailf mode is active, new events are prepended to the list.
 * Scroll is locked to the top (newest event) unless the user manually scrolls.
 * When tailf is off, scroll stays wherever the user left it.
 */
const MidiMonitorScroll = {
  mounted() {
    this._userScrolled = false

    this.el.addEventListener('scroll', () => {
      // If user scrolls down from top, disable auto-lock
      this._userScrolled = this.el.scrollTop > 40
    })

    this._scrollToTop()
  },

  updated() {
    const tailf = this.el.dataset.tailf === 'true'
    if (tailf && !this._userScrolled) {
      this._scrollToTop()
    }
  },

  _scrollToTop() {
    this.el.scrollTop = 0
  }
}

export default MidiMonitorScroll
