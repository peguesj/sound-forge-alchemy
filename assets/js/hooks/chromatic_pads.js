/**
 * ChromaticPads -- Web Audio pad engine for the sampler grid.
 *
 * Handles:
 * - Pad trigger via click/touch/keyboard (keys 1-9, 0, q-t, a-f map to pads 0-15)
 * - Per-pad volume, pitch shift, start/end time slicing
 * - Master volume control
 * - Drag-and-drop from the track browser sidebar to pads
 * - Visual feedback on trigger (flash animation)
 * - Web MIDI API integration for hardware controller input
 * - MIDI Learn mode for mapping hardware controls to pad parameters
 * - Preset import (.touchosc, .xpm, .pgm) via server-side parsing
 */
const ChromaticPads = {
  mounted() {
    this.audioCtx = null;
    this.buffers = {};       // pad_id -> AudioBuffer
    this.masterGain = null;
    this.activeNodes = {};   // pad_id -> {source, gain}

    // MIDI state
    this.midiAccess = null;
    this.midiInputs = [];
    this.midiLearnMode = false;
    this.midiLearnTarget = null;  // {type: "pad_trigger"|"pad_volume"|..., index: 0-15}
    this.midiMappings = [];       // [{midi_type, channel, number, action, parameter_index}]
    this.midiAvailable = false;
    this.lastMidiActivity = 0;

    this.initAudioContext();
    this.initWebMIDI();
    this.setupDragAndDrop();
    this.setupKeyboard();
    this.setupPadTriggers();

    // Listen for server-pushed audio load events
    this.handleEvent("load_pad_audio", ({pad_id, url}) => {
      this.loadAudio(pad_id, url);
    });

    this.handleEvent("set_master_volume", ({volume}) => {
      if (this.masterGain) {
        this.masterGain.gain.setValueAtTime(volume, this.audioCtx.currentTime);
      }
    });

    // MIDI Learn events from server
    this.handleEvent("enter_midi_learn", ({target_type, target_index}) => {
      this.midiLearnMode = true;
      this.midiLearnTarget = { type: target_type, index: target_index };
    });

    this.handleEvent("exit_midi_learn", () => {
      this.midiLearnMode = false;
      this.midiLearnTarget = null;
    });

    // Load MIDI mappings from server
    this.handleEvent("load_midi_mappings", ({mappings}) => {
      this.midiMappings = mappings || [];
    });
  },

  updated() {
    this.setupDragAndDrop();
    this.setupPadTriggers();
  },

  destroyed() {
    if (this.audioCtx) {
      this.audioCtx.close();
    }
    if (this._keyHandler) {
      document.removeEventListener("keydown", this._keyHandler);
    }
    this.teardownMIDI();
  },

  initAudioContext() {
    try {
      this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      this.masterGain = this.audioCtx.createGain();
      this.masterGain.connect(this.audioCtx.destination);
    } catch (_e) {
      console.warn("ChromaticPads: Web Audio not available");
    }
  },

  // =========================================================================
  // Web MIDI API
  // =========================================================================

  async initWebMIDI() {
    if (!navigator.requestMIDIAccess) {
      console.info("ChromaticPads: Web MIDI API not available in this browser");
      this.pushEvent("midi_status", { available: false, devices: [] });
      return;
    }

    try {
      this.midiAccess = await navigator.requestMIDIAccess({ sysex: false });
      this.midiAvailable = true;

      // Set up input listeners
      this.setupMIDIInputs();

      // Listen for connection changes (hot-plug)
      this.midiAccess.onstatechange = (event) => {
        this.setupMIDIInputs();
      };

      this.pushEvent("midi_status", {
        available: true,
        devices: this.getMIDIDeviceList()
      });
    } catch (err) {
      console.warn("ChromaticPads: Web MIDI access denied:", err);
      this.pushEvent("midi_status", { available: false, devices: [] });
    }
  },

  setupMIDIInputs() {
    // Remove old listeners
    for (const input of this.midiInputs) {
      input.onmidimessage = null;
    }
    this.midiInputs = [];

    if (!this.midiAccess) return;

    for (const input of this.midiAccess.inputs.values()) {
      if (input.state === "connected") {
        input.onmidimessage = (event) => this.handleMIDIMessage(event);
        this.midiInputs.push(input);
      }
    }

    // Notify server of device list update
    this.pushEvent("midi_devices_updated", {
      devices: this.getMIDIDeviceList()
    });
  },

  getMIDIDeviceList() {
    if (!this.midiAccess) return [];

    const devices = [];
    for (const input of this.midiAccess.inputs.values()) {
      devices.push({
        id: input.id,
        name: input.name || "Unknown Device",
        manufacturer: input.manufacturer || "",
        state: input.state
      });
    }
    return devices;
  },

  teardownMIDI() {
    for (const input of this.midiInputs) {
      input.onmidimessage = null;
    }
    this.midiInputs = [];
  },

  handleMIDIMessage(event) {
    const data = event.data;
    if (!data || data.length < 1) return;

    const statusByte = data[0];

    // Skip system real-time messages (clock, active sensing, etc.)
    if (statusByte >= 0xF0) return;

    const type = statusByte & 0xF0;
    const channel = statusByte & 0x0F;
    const byte1 = data.length > 1 ? data[1] : 0;
    const byte2 = data.length > 2 ? data[2] : 0;

    // Parse message type
    let midiType, number, value;
    if (type === 0x90 && byte2 > 0) {
      midiType = "note_on";
      number = byte1;
      value = byte2;
    } else if (type === 0x80 || (type === 0x90 && byte2 === 0)) {
      midiType = "note_off";
      number = byte1;
      value = byte2;
    } else if (type === 0xB0) {
      midiType = "cc";
      number = byte1;
      value = byte2;
    } else if (type === 0xC0) {
      midiType = "program_change";
      number = byte1;
      value = 0;
    } else {
      return; // Ignore other message types
    }

    // Update MIDI activity indicator
    this.lastMidiActivity = Date.now();
    this.pushEvent("midi_activity", { type: midiType, channel, number, value });

    // MIDI Learn mode: capture the message and send to server
    if (this.midiLearnMode && this.midiLearnTarget) {
      // Only capture note_on and cc for learn mode
      if (midiType === "note_on" || midiType === "cc") {
        const deviceName = event.target ? (event.target.name || "Web MIDI") : "Web MIDI";
        this.pushEvent("midi_learned", {
          device_name: deviceName,
          midi_type: midiType,
          channel: channel,
          number: number,
          target_type: this.midiLearnTarget.type,
          target_index: this.midiLearnTarget.index
        });
        this.midiLearnMode = false;
        this.midiLearnTarget = null;
      }
      return;
    }

    // Normal mode: route MIDI through mappings
    this.routeMIDIMessage(midiType, channel, number, value);
  },

  routeMIDIMessage(midiType, channel, number, value) {
    // Find matching mapping
    const mapping = this.midiMappings.find(m =>
      m.midi_type === midiType &&
      m.channel === channel &&
      m.number === number
    );

    if (!mapping) return;

    const padIndex = mapping.parameter_index;
    const padEl = this.el.querySelector(`[data-pad-index="${padIndex}"]`);
    if (!padEl) return;

    const padId = padEl.dataset.padId;
    if (!padId) return;

    switch (mapping.action) {
      case "pad_trigger": {
        if (midiType === "note_off" || value === 0) return;
        const opts = {
          volume: padEl.dataset.padVolume,
          pitch: padEl.dataset.padPitch,
          velocity: (value / 127).toFixed(4),
          start_time: padEl.dataset.padStartTime,
          end_time: padEl.dataset.padEndTime
        };
        this.triggerPad(padId, opts);
        this.pushEvent("pad_triggered", { pad_id: padId });
        break;
      }

      case "pad_volume": {
        const volume = Math.round(value / 127 * 100);
        this.pushEvent("update_pad_volume", { "pad-id": padId, value: String(volume) });
        break;
      }

      case "pad_pitch": {
        // Map 0-127 CC to -24..+24 semitones
        const pitch = Math.round(value / 127 * 48 - 24);
        this.pushEvent("update_pad_pitch", { "pad-id": padId, value: String(pitch) });
        break;
      }

      case "pad_velocity": {
        const vel = Math.round(value / 127 * 100);
        this.pushEvent("update_pad_velocity", { "pad-id": padId, value: String(vel) });
        break;
      }

      case "pad_master_volume": {
        const masterVol = Math.round(value / 127 * 100);
        this.pushEvent("set_master_volume", { value: String(masterVol) });
        break;
      }

      default:
        break;
    }
  },

  // =========================================================================
  // Audio Playback
  // =========================================================================

  async loadAudio(padId, url) {
    if (!this.audioCtx || !url) return;
    try {
      const resp = await fetch(url);
      const arrayBuffer = await resp.arrayBuffer();
      this.buffers[padId] = await this.audioCtx.decodeAudioData(arrayBuffer);
    } catch (e) {
      console.warn(`ChromaticPads: Failed to load audio for pad ${padId}:`, e);
    }
  },

  triggerPad(padId, opts = {}) {
    if (!this.audioCtx || !this.buffers[padId]) return;

    // Resume audio context if suspended (autoplay policy)
    if (this.audioCtx.state === "suspended") {
      this.audioCtx.resume();
    }

    // Stop any currently playing instance on this pad
    if (this.activeNodes[padId]) {
      try { this.activeNodes[padId].source.stop(); } catch (_) {}
    }

    const buffer = this.buffers[padId];
    const source = this.audioCtx.createBufferSource();
    const gainNode = this.audioCtx.createGain();

    source.buffer = buffer;

    // Apply pitch shift (semitones -> playbackRate)
    const pitch = parseFloat(opts.pitch || 0);
    source.playbackRate.value = Math.pow(2, pitch / 12);

    // Apply volume and velocity
    const volume = parseFloat(opts.volume ?? 1.0);
    const velocity = parseFloat(opts.velocity ?? 1.0);
    gainNode.gain.value = volume * velocity;

    source.connect(gainNode);
    gainNode.connect(this.masterGain);

    // Start/end time slicing
    const startTime = parseFloat(opts.start_time || 0);
    const endTime = opts.end_time ? parseFloat(opts.end_time) : undefined;
    const duration = endTime ? endTime - startTime : undefined;

    source.start(0, startTime, duration);
    this.activeNodes[padId] = { source, gain: gainNode };

    source.onended = () => {
      delete this.activeNodes[padId];
    };

    // Visual flash
    const padEl = this.el.querySelector(`[data-pad-id="${padId}"]`);
    if (padEl) {
      padEl.classList.add("ring-2", "ring-white", "scale-95");
      setTimeout(() => {
        padEl.classList.remove("ring-2", "ring-white", "scale-95");
      }, 150);
    }
  },

  // =========================================================================
  // Pad Triggers, Keyboard, Drag & Drop
  // =========================================================================

  setupPadTriggers() {
    this.el.querySelectorAll("[data-pad-id]").forEach(padEl => {
      const padId = padEl.dataset.padId;

      const handler = (e) => {
        e.preventDefault();
        const opts = {
          volume: padEl.dataset.padVolume,
          pitch: padEl.dataset.padPitch,
          velocity: padEl.dataset.padVelocity,
          start_time: padEl.dataset.padStartTime,
          end_time: padEl.dataset.padEndTime
        };
        this.triggerPad(padId, opts);
        this.pushEvent("pad_triggered", { pad_id: padId });
      };

      // Remove existing listeners to avoid duplicates
      padEl.removeEventListener("mousedown", padEl._cpHandler);
      padEl.removeEventListener("touchstart", padEl._cpHandler);
      padEl._cpHandler = handler;
      padEl.addEventListener("mousedown", handler);
      padEl.addEventListener("touchstart", handler, { passive: false });
    });
  },

  setupKeyboard() {
    // Map keyboard keys to pad indices (0-15)
    const keyMap = {
      "1": 0, "2": 1, "3": 2, "4": 3,
      "q": 4, "w": 5, "e": 6, "r": 7,
      "a": 8, "s": 9, "d": 10, "f": 11,
      "z": 12, "x": 13, "c": 14, "v": 15
    };

    this._keyHandler = (e) => {
      // Skip if typing in an input
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable) return;
      const padIndex = keyMap[e.key.toLowerCase()];
      if (padIndex === undefined) return;

      const padEl = this.el.querySelector(`[data-pad-index="${padIndex}"]`);
      if (!padEl) return;

      const padId = padEl.dataset.padId;
      if (!padId) return;

      const opts = {
        volume: padEl.dataset.padVolume,
        pitch: padEl.dataset.padPitch,
        velocity: padEl.dataset.padVelocity,
        start_time: padEl.dataset.padStartTime,
        end_time: padEl.dataset.padEndTime
      };
      this.triggerPad(padId, opts);
      this.pushEvent("pad_triggered", { pad_id: padId });
    };

    document.addEventListener("keydown", this._keyHandler);
  },

  setupDragAndDrop() {
    // Make external stem items draggable onto pads
    this.el.querySelectorAll("[data-stem-drag]").forEach(item => {
      item.setAttribute("draggable", true);
      item.addEventListener("dragstart", (e) => {
        e.dataTransfer.setData("text/plain", item.dataset.stemDrag);
        e.dataTransfer.effectAllowed = "copy";
        item.classList.add("opacity-50");
      });
      item.addEventListener("dragend", () => {
        item.classList.remove("opacity-50");
      });
    });

    // Make pad cells drop targets
    this.el.querySelectorAll("[data-pad-drop]").forEach(pad => {
      pad.addEventListener("dragover", (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
        pad.classList.add("ring-2", "ring-purple-500");
      });
      pad.addEventListener("dragleave", () => {
        pad.classList.remove("ring-2", "ring-purple-500");
      });
      pad.addEventListener("drop", (e) => {
        e.preventDefault();
        pad.classList.remove("ring-2", "ring-purple-500");
        const stemId = e.dataTransfer.getData("text/plain");
        if (stemId) {
          this.pushEvent("assign_stem", {
            pad_id: pad.dataset.padDrop,
            stem_id: stemId
          });
        }
      });
    });
  }
};

export default ChromaticPads;
