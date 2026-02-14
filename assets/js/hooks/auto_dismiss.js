const AutoDismiss = {
  mounted() {
    const delay = parseInt(this.el.dataset.dismissAfter || "5000", 10)
    this._timer = setTimeout(() => {
      this.el.style.transition = "opacity 300ms ease-out"
      this.el.style.opacity = "0"
      setTimeout(() => {
        this.el.style.display = "none"
        this.pushEvent("lv:clear-flash", { key: this.el.id === "flash-error" ? "error" : "info" })
      }, 300)
    }, delay)
  },
  destroyed() {
    if (this._timer) clearTimeout(this._timer)
  }
}

export default AutoDismiss
