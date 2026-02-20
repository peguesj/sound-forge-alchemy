const ResizeObserverHook = {
  mounted() {
    this.observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        this.pushEvent("chart_resized", { 
          id: this.el.id, 
          width: Math.round(width), 
          height: Math.round(height) 
        });
      }
    });
    this.observer.observe(this.el);
  },
  destroyed() {
    if (this.observer) this.observer.disconnect();
  }
};
export default ResizeObserverHook;
