/**
 * DebugLogScroll - Auto-scrolls the debug log container to the bottom
 * when new log entries are added, unless the user has scrolled up.
 */
const DebugLogScroll = {
  mounted() {
    this._autoScroll = true
    this.el.addEventListener("scroll", () => {
      const { scrollTop, scrollHeight, clientHeight } = this.el
      this._autoScroll = scrollHeight - scrollTop - clientHeight < 50
    })
    // Initial scroll to bottom
    this.el.scrollTop = this.el.scrollHeight
  },

  updated() {
    if (this._autoScroll) {
      this.el.scrollTop = this.el.scrollHeight
    }
  }
}

export default DebugLogScroll
