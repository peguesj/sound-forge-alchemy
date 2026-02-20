const StemMixerHook = {
  mounted() {
    this.faders = this.el.querySelectorAll('[data-fader]');
    this.activeFader = null;
    this.lastSentAt = 0;
    this.throttleMs = 16; // ~60fps

    this.el.addEventListener('touchstart', (e) => this.onTouchStart(e), { passive: false });
    this.el.addEventListener('touchmove', (e) => this.onTouchMove(e), { passive: false });
    this.el.addEventListener('touchend', (e) => this.onTouchEnd(e));

    // Mouse support for desktop testing
    this.el.addEventListener('mousedown', (e) => this.onMouseDown(e));
    document.addEventListener('mousemove', (e) => this.onMouseMove(e));
    document.addEventListener('mouseup', (e) => this.onMouseUp(e));

    // Handle incoming value updates from server
    this.handleEvent("stem_volume_update", ({ stem, value }) => {
      const fader = this.el.querySelector(`[data-fader="${stem}"]`);
      if (fader && fader !== this.activeFader) {
        this.setFaderPosition(fader, value);
      }
    });

    // Landscape detection
    this.checkOrientation();
    window.addEventListener('orientationchange', () => this.checkOrientation());
    window.addEventListener('resize', () => this.checkOrientation());
  },

  destroyed() {
    window.removeEventListener('orientationchange', () => this.checkOrientation());
    window.removeEventListener('resize', () => this.checkOrientation());
  },

  onTouchStart(e) {
    const fader = e.target.closest('[data-fader]');
    if (fader) {
      e.preventDefault();
      this.activeFader = fader;
      this.updateFaderFromTouch(fader, e.touches[0]);
    }
  },

  onTouchMove(e) {
    if (this.activeFader) {
      e.preventDefault();
      const now = Date.now();
      if (now - this.lastSentAt >= this.throttleMs) {
        this.updateFaderFromTouch(this.activeFader, e.touches[0]);
        this.lastSentAt = now;
      }
    }
  },

  onTouchEnd(_e) {
    this.activeFader = null;
  },

  onMouseDown(e) {
    const fader = e.target.closest('[data-fader]');
    if (fader) {
      this.activeFader = fader;
      this.updateFaderFromMouse(fader, e);
    }
  },

  onMouseMove(e) {
    if (this.activeFader) {
      const now = Date.now();
      if (now - this.lastSentAt >= this.throttleMs) {
        this.updateFaderFromMouse(this.activeFader, e);
        this.lastSentAt = now;
      }
    }
  },

  onMouseUp(_e) {
    this.activeFader = null;
  },

  updateFaderFromTouch(fader, touch) {
    const rect = fader.getBoundingClientRect();
    const y = touch.clientY - rect.top;
    const value = 1 - Math.max(0, Math.min(1, y / rect.height));
    this.setFaderPosition(fader, value);
    this.pushEvent("stem_volume_change", {
      stem: parseInt(fader.dataset.fader),
      value: Math.round(value * 100) / 100
    });
  },

  updateFaderFromMouse(fader, e) {
    const rect = fader.getBoundingClientRect();
    const y = e.clientY - rect.top;
    const value = 1 - Math.max(0, Math.min(1, y / rect.height));
    this.setFaderPosition(fader, value);
    this.pushEvent("stem_volume_change", {
      stem: parseInt(fader.dataset.fader),
      value: Math.round(value * 100) / 100
    });
  },

  setFaderPosition(fader, value) {
    const fill = fader.querySelector('[data-fader-fill]');
    const thumb = fader.querySelector('[data-fader-thumb]');
    if (fill) fill.style.height = `${value * 100}%`;
    if (thumb) thumb.style.bottom = `${value * 100}%`;
    fader.dataset.value = value;
  },

  checkOrientation() {
    const isLandscape = window.innerWidth > window.innerHeight;
    this.el.classList.toggle('landscape-mode', isLandscape);
  }
};

export default StemMixerHook;
