/**
 * DawEditor Hook - Per-stem WaveSurfer waveform with Regions plugin
 *
 * Each stem gets its own WaveSurfer instance with draggable/resizable regions
 * representing edit operations. WaveSurfer audio is muted since playback is
 * handled by the main audio engine.
 *
 * Visual effects by operation type:
 *   - Crop: grays out audio OUTSIDE the selected region (keep only region)
 *   - Trim: grays out audio INSIDE the selected region (remove region)
 *   - Fade In: green gradient overlay, opacity increasing left to right
 *   - Fade Out: green gradient overlay, opacity decreasing left to right
 *   - Split: bright yellow vertical line at cursor position, draggable,
 *            with distinct left (blue tint) and right (amber tint) sides
 *   - Gain: solid orange overlay, opacity proportional to gain level
 *
 * Data attributes (set by DawLive):
 *   data-stem-id       - UUID of the stem
 *   data-stem-type     - e.g. "vocals", "drums", "bass"
 *   data-stem-url      - URL to the stem audio file (/files/...)
 *   data-operations    - JSON array of existing edit operations
 *   data-operation-colors - JSON map of operation_type -> hex color
 */
import WaveSurfer from "wavesurfer.js"
import RegionsPlugin from "wavesurfer.js/dist/plugins/regions.esm.js"

const DawEditor = {
  mounted() {
    this.stemId = this.el.dataset.stemId
    this.stemType = this.el.dataset.stemType
    this.stemUrl = this.el.dataset.stemUrl
    this.operations = JSON.parse(this.el.dataset.operations || "[]")
    this.operationColors = JSON.parse(this.el.dataset.operationColors || "{}")

    // Map from operation_id -> region instance
    this.regionMap = {}

    // Map from operation_id -> { type, overlayEls: [...] }
    this.overlayMap = {}

    // Map from wavesurfer-generated region id -> operation_id (once assigned)
    this.pendingRegions = {}

    this._initWaveSurfer()
    this._setupServerEvents()

    // Register this stem editor instance on a global registry so the
    // DawPreview hook can access all stems' wavesurfer + audio buffers.
    if (!window.__dawEditors) window.__dawEditors = {}
    window.__dawEditors[this.stemId] = this
  },

  _initWaveSurfer() {
    // Create regions plugin
    this.regions = RegionsPlugin.create()

    // Create WaveSurfer instance
    this.wavesurfer = WaveSurfer.create({
      container: this.el,
      waveColor: this._waveColor(),
      progressColor: this._progressColor(),
      cursorColor: "#c084fc",
      height: 96,
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      interact: true,
      url: this.stemUrl,
      normalize: true,
      plugins: [this.regions],
    })

    // Mute wavesurfer audio - DAW uses separate playback engine
    this.wavesurfer.on("ready", () => {
      this.wavesurfer.setMuted(true)
      this.duration = this.wavesurfer.getDuration()
      this._renderExistingOperations()
    })

    this.wavesurfer.on("error", (error) => {
      console.error(`[DawEditor:${this.stemType}] WaveSurfer error:`, error)
    })

    // Region events
    this.regions.on("region-created", (region) => {
      // Only handle user-created regions (not programmatic ones)
      if (region._programmatic) return

      this.pushEvent("region_created", {
        stem_id: this.stemId,
        start: region.start,
        end: region.end,
        region_id: region.id,
      })
    })

    this.regions.on("region-updated", (region) => {
      const operationId = this._getOperationId(region)
      if (!operationId) return

      this.pushEvent("region_updated", {
        operation_id: operationId,
        stem_id: this.stemId,
        start: region.start,
        end: region.end,
      })

      // Update overlays for this operation after region drag/resize
      this._updateOverlayForRegion(operationId, region)
    })

    // Enable region creation on double-click
    this.regions.enableDragSelection({
      color: "rgba(139, 92, 246, 0.3)",
    })
  },

  _setupServerEvents() {
    // Server pushes after creating an operation from region_created
    this.handleEvent("operation_created", ({ stem_id, operation_id, region_id, operation_type, params }) => {
      if (stem_id !== this.stemId) return

      // Associate the wavesurfer region with the operation_id
      const region = this._findRegionById(region_id)
      if (region) {
        region._operationId = operation_id
        region._operationType = operation_type
        this.regionMap[operation_id] = region
        this._createOverlayForRegion(operation_id, operation_type, region, params)
      }
    })

    // Server pushes to add a region (from toolbar apply_operation)
    this.handleEvent("add_region", ({ stem_id, operation_id, operation_type, color, params }) => {
      if (stem_id !== this.stemId) return

      const region = this.regions.addRegion({
        start: params.start || 0,
        end: params.end || 5,
        color: this._regionColor(color),
        drag: true,
        resize: true,
        id: `op-${operation_id}`,
      })

      region._programmatic = true
      region._operationId = operation_id
      region._operationType = operation_type
      this.regionMap[operation_id] = region
      this._createOverlayForRegion(operation_id, operation_type, region, params)
    })

    // Server pushes to remove a region (from undo)
    this.handleEvent("remove_region", ({ stem_id, operation_id }) => {
      if (stem_id !== this.stemId) return

      const region = this.regionMap[operation_id]
      if (region) {
        region.remove()
        delete this.regionMap[operation_id]
      }
      this._removeOverlay(operation_id)
      this._removeSplitMarker(operation_id)
    })

    // Server asks for current cursor position to create a split at that point
    this.handleEvent("request_cursor_for_split", ({ stem_id }) => {
      if (stem_id !== this.stemId) return

      const cursorPosition = this._getCursorPosition()
      this.pushEvent("apply_split", {
        stem_id: this.stemId,
        cursor_position: cursorPosition,
      })
    })

    // Server pushes a split marker after creating a split operation
    this.handleEvent("add_split_marker", ({ stem_id, operation_id, position_sec, color }) => {
      if (stem_id !== this.stemId) return

      this._renderSplitMarker(operation_id, position_sec, color)
    })
  },

  _renderExistingOperations() {
    this.operations.forEach((op) => {
      // Split operations render as vertical markers, not regions
      if (op.operation_type === "split") {
        const positionSec = op.params?.position_sec ?? 5.0
        const color = op.color || this.operationColors["split"] || "#eab308"
        this._renderSplitMarker(op.id, positionSec, color)
        return
      }

      const start = op.params?.start ?? 0
      const end = op.params?.end ?? 5
      const color = op.color || this.operationColors[op.operation_type] || "#6b7280"

      const region = this.regions.addRegion({
        start: start,
        end: end,
        color: this._regionColor(color),
        drag: true,
        resize: true,
        id: `op-${op.id}`,
        content: op.operation_type,
      })

      region._programmatic = true
      region._operationId = op.id
      region._operationType = op.operation_type
      this.regionMap[op.id] = region
      this._createOverlayForRegion(op.id, op.operation_type, region, op.params)
    })
  },

  // -- Overlay management for operation visual effects --

  /**
   * Get the WaveSurfer waveform wrapper element for positioning overlays.
   * WaveSurfer renders a shadow DOM; we position overlays relative to this.el.
   */
  _getWaveformWrapper() {
    // WaveSurfer v7 renders into the container element directly
    return this.el
  },

  /**
   * Convert a time (seconds) to a percentage of total duration.
   */
  _timeToPercent(timeSec) {
    if (!this.duration || this.duration <= 0) return 0
    return Math.max(0, Math.min(100, (timeSec / this.duration) * 100))
  },

  /**
   * Create overlay divs for an operation's visual effect.
   * - Crop: two overlays (left of start, right of end) to gray out outside
   * - Trim: one overlay covering start..end to gray out inside
   * - Fade In: green gradient overlay, opacity increasing left to right
   * - Fade Out: green gradient overlay, opacity decreasing left to right
   * - Gain: solid orange overlay, opacity proportional to gain level
   */
  _createOverlayForRegion(operationId, operationType, region, params) {
    // Only specific types get visual overlays
    const overlayTypes = ["crop", "trim", "fade_in", "fade_out", "gain"]
    if (!overlayTypes.includes(operationType)) return

    const wrapper = this._getWaveformWrapper()
    if (!wrapper) return

    // Ensure wrapper has relative positioning for absolute children
    if (getComputedStyle(wrapper).position === "static") {
      wrapper.style.position = "relative"
    }

    const startPct = this._timeToPercent(region.start)
    const endPct = this._timeToPercent(region.end)
    const overlayEls = []

    if (operationType === "crop") {
      // Crop: gray out everything OUTSIDE the region
      // Left overlay: 0% to startPct
      if (startPct > 0) {
        const leftOverlay = this._createOverlayEl(operationId, "crop")
        leftOverlay.style.left = "0%"
        leftOverlay.style.width = `${startPct}%`
        wrapper.appendChild(leftOverlay)
        overlayEls.push(leftOverlay)
      }

      // Right overlay: endPct to 100%
      if (endPct < 100) {
        const rightOverlay = this._createOverlayEl(operationId, "crop")
        rightOverlay.style.left = `${endPct}%`
        rightOverlay.style.width = `${100 - endPct}%`
        wrapper.appendChild(rightOverlay)
        overlayEls.push(rightOverlay)
      }
    } else if (operationType === "trim") {
      // Trim: gray out everything INSIDE the region
      const trimOverlay = this._createOverlayEl(operationId, "trim")
      trimOverlay.style.left = `${startPct}%`
      trimOverlay.style.width = `${endPct - startPct}%`
      wrapper.appendChild(trimOverlay)
      overlayEls.push(trimOverlay)
    } else if (operationType === "fade_in") {
      // Fade in: green gradient, opacity increasing left to right
      const fadeOverlay = this._createOverlayEl(operationId, "fade_in")
      fadeOverlay.style.left = `${startPct}%`
      fadeOverlay.style.width = `${endPct - startPct}%`
      wrapper.appendChild(fadeOverlay)
      overlayEls.push(fadeOverlay)
    } else if (operationType === "fade_out") {
      // Fade out: green gradient, opacity decreasing left to right
      const fadeOverlay = this._createOverlayEl(operationId, "fade_out")
      fadeOverlay.style.left = `${startPct}%`
      fadeOverlay.style.width = `${endPct - startPct}%`
      wrapper.appendChild(fadeOverlay)
      overlayEls.push(fadeOverlay)
    } else if (operationType === "gain") {
      // Gain: solid orange overlay with opacity proportional to gain level
      const level = (params && (params.level ?? params.gain)) || 1.0
      const gainOverlay = this._createOverlayEl(operationId, "gain", { level })
      gainOverlay.style.left = `${startPct}%`
      gainOverlay.style.width = `${endPct - startPct}%`
      wrapper.appendChild(gainOverlay)
      overlayEls.push(gainOverlay)
    }

    this.overlayMap[operationId] = { type: operationType, overlayEls, params }
  },

  /**
   * Create a single overlay div element with consistent styling.
   */
  _createOverlayEl(operationId, type, opts = {}) {
    const el = document.createElement("div")
    el.dataset.overlayFor = operationId
    el.dataset.overlayType = type
    el.style.position = "absolute"
    el.style.top = "0"
    el.style.height = "100%"
    el.style.pointerEvents = "none"
    el.style.zIndex = "5"
    el.style.transition = "left 0.1s ease, width 0.1s ease"

    if (type === "crop") {
      // Grayed out = dark semi-transparent with diagonal stripes
      el.style.backgroundColor = "rgba(0, 0, 0, 0.45)"
      el.style.backgroundImage =
        "repeating-linear-gradient(45deg, transparent, transparent 4px, rgba(0,0,0,0.15) 4px, rgba(0,0,0,0.15) 8px)"
    } else if (type === "trim") {
      // Trimmed region = red-tinted semi-transparent with cross-hatch
      el.style.backgroundColor = "rgba(239, 68, 68, 0.3)"
      el.style.backgroundImage =
        "repeating-linear-gradient(45deg, transparent, transparent 4px, rgba(239,68,68,0.15) 4px, rgba(239,68,68,0.15) 8px)"
    } else if (type === "fade_in") {
      // Fade in: green gradient, transparent on left -> opaque on right
      // Shows the fade direction (silence -> full volume)
      el.style.background =
        "linear-gradient(to right, rgba(34, 197, 94, 0.05), rgba(34, 197, 94, 0.4))"
      el.style.borderLeft = "2px solid rgba(34, 197, 94, 0.6)"
      el.style.borderRight = "2px solid rgba(34, 197, 94, 0.8)"
    } else if (type === "fade_out") {
      // Fade out: green gradient, opaque on left -> transparent on right
      // Shows the fade direction (full volume -> silence)
      el.style.background =
        "linear-gradient(to right, rgba(34, 197, 94, 0.4), rgba(34, 197, 94, 0.05))"
      el.style.borderLeft = "2px solid rgba(34, 197, 94, 0.8)"
      el.style.borderRight = "2px solid rgba(34, 197, 94, 0.6)"
    } else if (type === "gain") {
      // Gain: solid orange overlay with opacity proportional to gain level.
      // level=0 is nearly transparent, level=1 is baseline (0.25 opacity),
      // level>1 (boost) increases opacity up to 0.5.
      const level = opts.level ?? 1.0
      const opacity = Math.min(0.5, Math.max(0.08, level * 0.25))
      el.style.backgroundColor = `rgba(249, 115, 22, ${opacity})`
      el.style.borderTop = "2px solid rgba(249, 115, 22, 0.6)"
      el.style.borderBottom = "2px solid rgba(249, 115, 22, 0.6)"
      // Store level on the element for update convenience
      el.dataset.gainLevel = level
    }

    return el
  },

  /**
   * Update overlay positions when a region is dragged/resized.
   */
  _updateOverlayForRegion(operationId, region) {
    const overlayInfo = this.overlayMap[operationId]
    if (!overlayInfo) return

    const startPct = this._timeToPercent(region.start)
    const endPct = this._timeToPercent(region.end)

    if (overlayInfo.type === "crop") {
      // Remove old overlays and recreate (simpler than tracking left/right)
      this._removeOverlay(operationId)
      this._createOverlayForRegion(operationId, "crop", region)
    } else if (overlayInfo.type === "trim" || overlayInfo.type === "fade_in" ||
               overlayInfo.type === "fade_out") {
      // Single overlay positioned at the region bounds
      const el = overlayInfo.overlayEls[0]
      if (el) {
        el.style.left = `${startPct}%`
        el.style.width = `${endPct - startPct}%`
      }
    } else if (overlayInfo.type === "gain") {
      const el = overlayInfo.overlayEls[0]
      if (el) {
        el.style.left = `${startPct}%`
        el.style.width = `${endPct - startPct}%`
      }
    }
  },

  /**
   * Remove overlay divs for an operation (used by undo and updates).
   */
  _removeOverlay(operationId) {
    const overlayInfo = this.overlayMap[operationId]
    if (!overlayInfo) return

    overlayInfo.overlayEls.forEach((el) => {
      if (el.parentNode) {
        el.parentNode.removeChild(el)
      }
    })

    delete this.overlayMap[operationId]
  },

  // -- Cursor position --

  /**
   * Get the current cursor/playback position from WaveSurfer in seconds.
   * Falls back to 0 if wavesurfer is not ready.
   */
  _getCursorPosition() {
    if (!this.wavesurfer) return 0
    return this.wavesurfer.getCurrentTime() || 0
  },

  // -- Split marker rendering --

  /**
   * Map from operation_id -> { line, leftTint, rightTint, handleEl } for split markers.
   */
  _splitMarkers: null,

  _getSplitMarkers() {
    if (!this._splitMarkers) this._splitMarkers = {}
    return this._splitMarkers
  },

  /**
   * Render a visual split marker at the given position.
   * Draws a bright yellow vertical line with slightly different background tints
   * on each side. The line is draggable to update the split position.
   */
  _renderSplitMarker(operationId, positionSec, color) {
    const wrapper = this._getWaveformWrapper()
    if (!wrapper) return

    if (getComputedStyle(wrapper).position === "static") {
      wrapper.style.position = "relative"
    }

    const positionPct = this._timeToPercent(positionSec)
    const markers = this._getSplitMarkers()

    // Left tint (slightly darker, blue-ish tint)
    const leftTint = document.createElement("div")
    leftTint.dataset.splitFor = operationId
    leftTint.dataset.splitPart = "left"
    leftTint.style.position = "absolute"
    leftTint.style.top = "0"
    leftTint.style.left = "0%"
    leftTint.style.width = `${positionPct}%`
    leftTint.style.height = "100%"
    leftTint.style.backgroundColor = "rgba(59, 130, 246, 0.06)"
    leftTint.style.pointerEvents = "none"
    leftTint.style.zIndex = "4"
    leftTint.style.transition = "width 0.05s ease"
    wrapper.appendChild(leftTint)

    // Right tint (slightly warmer, amber-ish tint)
    const rightTint = document.createElement("div")
    rightTint.dataset.splitFor = operationId
    rightTint.dataset.splitPart = "right"
    rightTint.style.position = "absolute"
    rightTint.style.top = "0"
    rightTint.style.left = `${positionPct}%`
    rightTint.style.width = `${100 - positionPct}%`
    rightTint.style.height = "100%"
    rightTint.style.backgroundColor = "rgba(251, 191, 36, 0.06)"
    rightTint.style.pointerEvents = "none"
    rightTint.style.zIndex = "4"
    rightTint.style.transition = "left 0.05s ease, width 0.05s ease"
    wrapper.appendChild(rightTint)

    // Vertical split line (bright yellow, high contrast)
    const line = document.createElement("div")
    line.dataset.splitFor = operationId
    line.dataset.splitPart = "line"
    line.style.position = "absolute"
    line.style.top = "0"
    line.style.left = `${positionPct}%`
    line.style.width = "3px"
    line.style.height = "100%"
    line.style.backgroundColor = color || "#eab308"
    line.style.boxShadow = `0 0 6px ${color || "#eab308"}, 0 0 12px rgba(234, 179, 8, 0.4)`
    line.style.zIndex = "10"
    line.style.cursor = "ew-resize"
    line.style.transform = "translateX(-50%)"
    line.style.transition = "left 0.05s ease"
    wrapper.appendChild(line)

    // Drag handle indicator (small diamond at center of line)
    const handle = document.createElement("div")
    handle.dataset.splitFor = operationId
    handle.dataset.splitPart = "handle"
    handle.style.position = "absolute"
    handle.style.top = "50%"
    handle.style.left = "50%"
    handle.style.width = "10px"
    handle.style.height = "10px"
    handle.style.backgroundColor = color || "#eab308"
    handle.style.border = "1px solid rgba(0,0,0,0.3)"
    handle.style.borderRadius = "2px"
    handle.style.transform = "translate(-50%, -50%) rotate(45deg)"
    handle.style.pointerEvents = "none"
    handle.style.zIndex = "11"
    line.appendChild(handle)

    // Make the line draggable
    this._makeSplitDraggable(line, operationId, leftTint, rightTint, wrapper)

    markers[operationId] = { line, leftTint, rightTint, positionSec }
  },

  /**
   * Make a split line element draggable horizontally.
   * On drag end, push the new position to the server.
   */
  _makeSplitDraggable(lineEl, operationId, leftTint, rightTint, wrapper) {
    let isDragging = false
    let startX = 0

    const onMouseDown = (e) => {
      isDragging = true
      startX = e.clientX
      e.preventDefault()
      e.stopPropagation()

      // Disable transitions during drag for responsiveness
      lineEl.style.transition = "none"
      leftTint.style.transition = "none"
      rightTint.style.transition = "none"

      document.addEventListener("mousemove", onMouseMove)
      document.addEventListener("mouseup", onMouseUp)
    }

    const onMouseMove = (e) => {
      if (!isDragging) return

      const rect = wrapper.getBoundingClientRect()
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
      const pct = (x / rect.width) * 100

      lineEl.style.left = `${pct}%`
      leftTint.style.width = `${pct}%`
      rightTint.style.left = `${pct}%`
      rightTint.style.width = `${100 - pct}%`
    }

    const onMouseUp = (e) => {
      if (!isDragging) return
      isDragging = false

      // Re-enable transitions
      lineEl.style.transition = "left 0.05s ease"
      leftTint.style.transition = "width 0.05s ease"
      rightTint.style.transition = "left 0.05s ease, width 0.05s ease"

      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)

      // Calculate new position in seconds
      const rect = wrapper.getBoundingClientRect()
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
      const pct = x / rect.width
      const newPositionSec = pct * (this.duration || 0)

      // Update local state
      const markers = this._getSplitMarkers()
      if (markers[operationId]) {
        markers[operationId].positionSec = newPositionSec
      }

      // Push updated position to server
      this.pushEvent("split_marker_moved", {
        operation_id: operationId,
        position_sec: newPositionSec,
      })
    }

    lineEl.addEventListener("mousedown", onMouseDown)

    // Store cleanup reference
    lineEl._splitCleanup = () => {
      lineEl.removeEventListener("mousedown", onMouseDown)
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
    }
  },

  /**
   * Remove a split marker and its tints from the DOM.
   */
  _removeSplitMarker(operationId) {
    const markers = this._getSplitMarkers()
    const marker = markers[operationId]
    if (!marker) return

    if (marker.line) {
      if (marker.line._splitCleanup) marker.line._splitCleanup()
      if (marker.line.parentNode) marker.line.parentNode.removeChild(marker.line)
    }
    if (marker.leftTint && marker.leftTint.parentNode) {
      marker.leftTint.parentNode.removeChild(marker.leftTint)
    }
    if (marker.rightTint && marker.rightTint.parentNode) {
      marker.rightTint.parentNode.removeChild(marker.rightTint)
    }

    delete markers[operationId]
  },

  // -- Region helpers --

  _findRegionById(regionId) {
    const allRegions = this.regions.getRegions()
    return allRegions.find((r) => r.id === regionId) || null
  },

  _getOperationId(region) {
    return region._operationId || null
  },

  _regionColor(hexColor) {
    // Convert hex to rgba with transparency for region overlay
    const hex = hexColor.replace("#", "")
    const r = parseInt(hex.substring(0, 2), 16)
    const g = parseInt(hex.substring(2, 4), 16)
    const b = parseInt(hex.substring(4, 6), 16)
    return `rgba(${r}, ${g}, ${b}, 0.3)`
  },

  _waveColor() {
    const colors = {
      vocals: "#a78bfa",
      drums: "#60a5fa",
      bass: "#4ade80",
      other: "#fbbf24",
      guitar: "#fb7185",
      piano: "#22d3ee",
      electric_guitar: "#f87171",
      acoustic_guitar: "#fb923c",
      synth: "#f472b6",
      strings: "#2dd4bf",
      wind: "#38bdf8",
    }
    return colors[this.stemType] || "#6b7280"
  },

  _progressColor() {
    const colors = {
      vocals: "#7c3aed",
      drums: "#2563eb",
      bass: "#16a34a",
      other: "#d97706",
      guitar: "#e11d48",
      piano: "#0891b2",
      electric_guitar: "#dc2626",
      acoustic_guitar: "#ea580c",
      synth: "#db2777",
      strings: "#0d9488",
      wind: "#0284c7",
    }
    return colors[this.stemType] || "#4b5563"
  },

  destroyed() {
    // Unregister from global registry
    if (window.__dawEditors && window.__dawEditors[this.stemId]) {
      delete window.__dawEditors[this.stemId]
    }

    // Clean up overlays
    Object.keys(this.overlayMap).forEach((opId) => this._removeOverlay(opId))

    // Clean up split markers
    const markers = this._getSplitMarkers()
    Object.keys(markers).forEach((opId) => this._removeSplitMarker(opId))

    if (this.wavesurfer) {
      this.wavesurfer.destroy()
      this.wavesurfer = null
    }
    this.regionMap = {}
    this.overlayMap = {}
    this._splitMarkers = {}
  },
}

export default DawEditor
