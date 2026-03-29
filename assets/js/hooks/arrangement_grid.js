/**
 * ArrangementGrid Hook — Multi-track stem arranger grid (Story 3.2)
 *
 * Renders a time-based grid where rows are stems and columns are 4-bar blocks.
 * Clicking a cell toggles that block muted/active. Drag to reposition blocks.
 *
 * data-stems:          JSON Array<{id, stem_type, label, color}>
 * data-arrangement:    JSON Object<stem_type → Array<{start_sec, end_sec, muted}>>
 * data-duration-sec:   Total track duration in seconds (float)
 * data-bpm:            Track BPM (float, default 120)
 */

const CELL_WIDTH = 48   // px per 4-bar block
const ROW_HEIGHT = 36   // px per stem row
const HEADER_HEIGHT = 24
const LABEL_WIDTH = 80

const ArrangementGrid = {
  mounted() {
    this.stems = this._parseJSON('stems', [])
    this.arrangement = this._parseJSON('arrangement', {})
    this.durationSec = parseFloat(this.el.dataset.durationSec || '120')
    this.bpm = parseFloat(this.el.dataset.bpm || '120')

    this.canvas = document.createElement('canvas')
    this.canvas.className = 'block w-full rounded cursor-pointer'
    this.el.appendChild(this.canvas)
    this.ctx = this.canvas.getContext('2d')

    this.canvas.addEventListener('click', (e) => this._handleClick(e))

    this.handleEvent('set_arrangement', ({ arrangement }) => {
      this.arrangement = arrangement || {}
      this.draw()
    })

    this.draw()
  },

  updated() {
    this.stems = this._parseJSON('stems', [])
    this.arrangement = this._parseJSON('arrangement', {})
    this.durationSec = parseFloat(this.el.dataset.durationSec || '120')
    this.bpm = parseFloat(this.el.dataset.bpm || '120')
    this.draw()
  },

  draw() {
    const secPerBeat = 60.0 / this.bpm
    const secPerBar = secPerBeat * 4
    const secPerBlock = secPerBar * 4   // 4 bars per cell
    const numBlocks = Math.max(1, Math.ceil(this.durationSec / secPerBlock))
    const numRows = this.stems.length

    const W = LABEL_WIDTH + numBlocks * CELL_WIDTH
    const H = HEADER_HEIGHT + numRows * ROW_HEIGHT

    const dpr = window.devicePixelRatio || 1
    this.canvas.width = W * dpr
    this.canvas.height = H * dpr
    this.canvas.style.width = W + 'px'
    this.canvas.style.height = H + 'px'
    const ctx = this.ctx
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

    // Background
    ctx.fillStyle = '#111827'
    ctx.fillRect(0, 0, W, H)

    // Time header
    ctx.fillStyle = '#374151'
    ctx.fillRect(LABEL_WIDTH, 0, W - LABEL_WIDTH, HEADER_HEIGHT)
    ctx.fillStyle = '#9ca3af'
    ctx.font = '9px sans-serif'
    ctx.textAlign = 'center'
    for (let b = 0; b < numBlocks; b++) {
      const x = LABEL_WIDTH + b * CELL_WIDTH + CELL_WIDTH / 2
      const bar = b * 4 + 1
      ctx.fillText(`B${bar}`, x, HEADER_HEIGHT - 6)
    }

    // Row backgrounds + labels
    this.stems.forEach((stem, rowIdx) => {
      const y = HEADER_HEIGHT + rowIdx * ROW_HEIGHT
      ctx.fillStyle = rowIdx % 2 === 0 ? '#1f2937' : '#111827'
      ctx.fillRect(0, y, W, ROW_HEIGHT)

      // Label
      ctx.fillStyle = '#d1d5db'
      ctx.font = '10px sans-serif'
      ctx.textAlign = 'right'
      ctx.fillText(stem.label || stem.stem_type, LABEL_WIDTH - 4, y + ROW_HEIGHT / 2 + 4)

      // Cells
      const blocks = this._blocksForStem(stem.stem_type, numBlocks, secPerBlock)
      blocks.forEach((block, blockIdx) => {
        const x = LABEL_WIDTH + blockIdx * CELL_WIDTH
        ctx.fillStyle = block.muted ? '#374151' : (stem.color || '#6d28d9')
        ctx.fillRect(x + 1, y + 2, CELL_WIDTH - 2, ROW_HEIGHT - 4)
      })
    })

    // Grid lines
    ctx.strokeStyle = '#374151'
    ctx.lineWidth = 0.5
    for (let b = 0; b <= numBlocks; b++) {
      const x = LABEL_WIDTH + b * CELL_WIDTH
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, H)
      ctx.stroke()
    }
    for (let r = 0; r <= numRows; r++) {
      const y = HEADER_HEIGHT + r * ROW_HEIGHT
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(W, y)
      ctx.stroke()
    }
  },

  _blocksForStem(stemType, numBlocks, secPerBlock) {
    const regions = (this.arrangement[stemType] || []).slice()
    return Array.from({ length: numBlocks }, (_, blockIdx) => {
      const blockStart = blockIdx * secPerBlock
      const blockEnd = blockStart + secPerBlock
      // Block is muted if a region covers it and is muted
      const region = regions.find(r => r.start_sec < blockEnd && r.end_sec > blockStart)
      return { muted: region ? region.muted : false }
    })
  },

  _handleClick(e) {
    const rect = this.canvas.getBoundingClientRect()
    const x = (e.clientX - rect.left) * (this.canvas.width / rect.width / (window.devicePixelRatio || 1))
    const y = (e.clientY - rect.top) * (this.canvas.height / rect.height / (window.devicePixelRatio || 1))

    if (x < LABEL_WIDTH || y < HEADER_HEIGHT) return

    const secPerBeat = 60.0 / this.bpm
    const secPerBlock = secPerBeat * 4 * 4
    const blockIdx = Math.floor((x - LABEL_WIDTH) / CELL_WIDTH)
    const rowIdx = Math.floor((y - HEADER_HEIGHT) / ROW_HEIGHT)

    if (rowIdx < 0 || rowIdx >= this.stems.length) return

    const stem = this.stems[rowIdx]
    const blockStart = blockIdx * secPerBlock
    const blockEnd = blockStart + secPerBlock

    this.pushEvent('toggle_arrangement_block', {
      stem_type: stem.stem_type,
      start_sec: blockStart,
      end_sec: blockEnd
    })
  },

  _parseJSON(key, fallback) {
    const raw = this.el.dataset[key.replace(/-([a-z])/g, (_, c) => c.toUpperCase())]
    if (!raw) return fallback
    try { return JSON.parse(raw) } catch { return fallback }
  }
}

export default ArrangementGrid
