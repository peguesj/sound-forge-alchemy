const SwipeHook = {
  mounted() {
    this.startX = 0;
    this.startY = 0;
    this.threshold = 50;

    this.el.addEventListener('touchstart', (e) => {
      this.startX = e.touches[0].clientX;
      this.startY = e.touches[0].clientY;
    }, { passive: true });

    this.el.addEventListener('touchend', (e) => {
      const dx = e.changedTouches[0].clientX - this.startX;
      const dy = e.changedTouches[0].clientY - this.startY;
      
      if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > this.threshold) {
        if (dx > 0) {
          this.pushEvent("swipe", { direction: "right" });
        } else {
          this.pushEvent("swipe", { direction: "left" });
        }
      }
    }, { passive: true });
  }
};
export default SwipeHook;
