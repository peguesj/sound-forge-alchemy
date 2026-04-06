/**
 * PianoRoll Hook - Canvas-based MIDI note visualization
 * Renders detected notes as colored rectangles on a time/pitch grid.
 */

const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
const MIN_PITCH = 36  // C2
const MAX_PITCH = 96  // C7
const KEY_HEIGHT = 8
const BLACK_KEYS = new Set([1, 3, 6, 8, 10])

function pitchToName(pitch) {
  const octave = Math.floor(pitch / 12) - 1
  return `${NOTE_NAMES[pitch % 12]}${octave}`
}

function velocityToColor(velocity) {
  // Purple gradient: low velocity = dim, high velocity = bright
  const v = Math.max(0, Math.min(1, velocity))
  const r = Math.round(120 + v * 48)
  const g = Math.round(50 + v * 82)
  const b = Math.round(200 + v * 55)
  return `rgb(${r}, ${g}, ${b})`
}

const PianoRoll = {
  mounted() {
    this.canvas = document.createElement('canvas')
    this.canvas.className = 'w-full rounded'
    this.canvas.style.height = '300px'
    this.el.appendChild(this.canvas)
    this.ctx = this.canvas.getContext('2d')

    this.scrollOffset = 0
    this.zoom = 1.0
    this.hoveredNote = null
    // User-drawn notes (Story 2.4) — keyed by id for optimistic updates
    this.userNotes = this._parseUserNotes()

    // Tooltip
    this.tooltip = document.createElement('div')
    this.tooltip.className = 'absolute hidden bg-gray-800 text-white text-xs px-2 py-1 rounded pointer-events-none z-50'
    this.el.style.position = 'relative'
    this.el.appendChild(this.tooltip)

    this.canvas.addEventListener('wheel', (e) => {
      e.preventDefault()
      if (e.ctrlKey || e.metaKey) {
        this.zoom = Math.max(0.25, Math.min(8, this.zoom * (1 - e.deltaY * 0.002)))
      } else {
        this.scrollOffset = Math.max(0, this.scrollOffset + e.deltaY * 0.5)
      }
      this.draw()
    })

    this.canvas.addEventListener('mousemove', (e) => {
      const rect = this.canvas.getBoundingClientRect()
      const x = e.clientX - rect.left
      const y = e.clientY - rect.top
      this.handleHover(x, y, e.clientX, e.clientY)
    })

    this.canvas.addEventListener('mouseleave', () => {
      this.tooltip.classList.add('hidden')
      this.hoveredNote = null
    })

    // Note edit click handler (Story 2.4)
    this.canvas.addEventListener('click', (e) => {
      if (!this.el.dataset.editable) return
      const rect = this.canvas.getBoundingClientRect()
      const x = e.clientX - rect.left
      const y = e.clientY - rect.top
      this.handleNoteClick(x, y)
    })

    // Receive user notes from server
    this.handleEvent('set_user_notes', ({ notes }) => {
      this.userNotes = notes || []
      this.draw()
    })

    this.draw()
  },

  updated() {
    this.userNotes = this._parseUserNotes()
    this.draw()
  },

  _parseUserNotes() {
    const raw = this.el.dataset.userNotes
    if (!raw) return []
    try { return JSON.parse(raw) } catch { return [] }
  },

  handleNoteClick(mx, my) {
    const notes = this.parseNotes()
    const rect = this.canvas.getBoundingClientRect()
    const W = rect.width
    const H = rect.height
    const pianoWidth = 40
    const pitchRange = MAX_PITCH - MIN_PITCH
    const noteHeight = (H - 20) / pitchRange
    const maxTime = notes.length > 0 ? Math.max(...notes.map(n => n.offset)) + 1 : 10
    const pxPerSec = ((W - pianoWidth) / maxTime) * this.zoom

    if (mx < pianoWidth) return  // click on piano key area — ignore

    // Map pixel coords back to pitch + onset
    const pitch = MAX_PITCH - 1 - Math.floor((my / (H - 20)) * pitchRange) + MIN_PITCH
    const onsetSec = (mx - pianoWidth + this.scrollOffset) / pxPerSec

    if (pitch < MIN_PITCH || pitch > MAX_PITCH || onsetSec < 0) return

    // Check if clicking on an existing user note to delete it
    const existingIdx = this.userNotes.findIndex(n => {
      const nx = pianoWidth + n.onset * pxPerSec - this.scrollOffset
      const nw = Math.max(2, (n.duration || 0.25) * pxPerSec)
      const ny = H - 20 - (n.note - MIN_PITCH + 1) * noteHeight
      const nh = Math.max(1, noteHeight - 1)
      return mx >= nx && mx <= nx + nw && my >= ny && my <= ny + nh
    })

    if (existingIdx >= 0) {
      const noteToDelete = this.userNotes[existingIdx]
      if (noteToDelete.id) {
        this.pushEvent('delete_user_note', { note_id: noteToDelete.id })
      }
      this.userNotes.splice(existingIdx, 1)
    } else {
      // Add new note optimistically
      const tempNote = { note: pitch, onset: onsetSec, offset: onsetSec + 0.25, duration: 0.25, velocity: 0.8, _temp: true }
      this.userNotes.push(tempNote)
      this.pushEvent('add_user_note', { note: pitch, onset_sec: onsetSec, duration_sec: 0.25, velocity: 0.8 })
    }

    this.draw()
  },

  parseNotes() {
    const raw = this.el.dataset.notes
    if (!raw) return []
    try {
      return JSON.parse(raw)
    } catch {
      return []
    }
  },

  draw() {
    const notes = this.parseNotes()
    const canvas = this.canvas
    const ctx = this.ctx

    // High DPI
    const rect = canvas.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    canvas.width = rect.width * dpr
    canvas.height = rect.height * dpr
    ctx.scale(dpr, dpr)
    const W = rect.width
    const H = rect.height

    // Clear
    ctx.fillStyle = '#1f2937'
    ctx.fillRect(0, 0, W, H)

    if (notes.length === 0) {
      ctx.fillStyle = '#6b7280'
      ctx.font = '14px sans-serif'
      ctx.textAlign = 'center'
      ctx.fillText('No MIDI data', W / 2, H / 2)
      return
    }

    const pianoWidth = 40
    const pitchRange = MAX_PITCH - MIN_PITCH
    const noteHeight = (H - 20) / pitchRange // 20px for time axis

    // Find time range
    const maxTime = Math.max(...notes.map(n => n.offset)) + 1
    const pxPerSec = ((W - pianoWidth) / maxTime) * this.zoom

    // Draw piano keys on left
    for (let p = MIN_PITCH; p < MAX_PITCH; p++) {
      const y = H - 20 - (p - MIN_PITCH + 1) * noteHeight
      const isBlack = BLACK_KEYS.has(p % 12)
      ctx.fillStyle = isBlack ? '#374151' : '#4b5563'
      ctx.fillRect(0, y, pianoWidth - 2, noteHeight)

      if (p % 12 === 0) {
        ctx.fillStyle = '#9ca3af'
        ctx.font = '9px sans-serif'
        ctx.textAlign = 'right'
        ctx.fillText(pitchToName(p), pianoWidth - 4, y + noteHeight * 0.75)
      }
    }

    // Draw grid lines
    ctx.strokeStyle = '#374151'
    ctx.lineWidth = 0.5
    for (let t = 0; t <= maxTime; t++) {
      const x = pianoWidth + t * pxPerSec - this.scrollOffset
      if (x < pianoWidth || x > W) continue
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, H - 20)
      ctx.stroke()

      // Time labels
      ctx.fillStyle = '#9ca3af'
      ctx.font = '9px sans-serif'
      ctx.textAlign = 'center'
      ctx.fillText(`${t}s`, x, H - 6)
    }

    // Draw notes
    ctx.save()
    ctx.beginPath()
    ctx.rect(pianoWidth, 0, W - pianoWidth, H - 20)
    ctx.clip()

    notes.forEach((note, idx) => {
      const x = pianoWidth + note.onset * pxPerSec - this.scrollOffset
      const w = Math.max(2, (note.offset - note.onset) * pxPerSec)
      const y = H - 20 - (note.note - MIN_PITCH + 1) * noteHeight
      const h = Math.max(1, noteHeight - 1)

      if (x + w < pianoWidth || x > W) return

      ctx.fillStyle = velocityToColor(note.velocity)
      ctx.fillRect(x, y, w, h)

      // Highlight on hover
      if (this.hoveredNote === idx) {
        ctx.strokeStyle = '#ffffff'
        ctx.lineWidth = 1.5
        ctx.strokeRect(x, y, w, h)
      }
    })

    ctx.restore()

    // Draw user-edited notes (Story 2.4) — teal, rendered above auto-detected notes
    ctx.save()
    ctx.beginPath()
    ctx.rect(pianoWidth, 0, W - pianoWidth, H - 20)
    ctx.clip()

    ;(this.userNotes || []).forEach((note) => {
      const x = pianoWidth + note.onset * pxPerSec - this.scrollOffset
      const w = Math.max(2, (note.duration || 0.25) * pxPerSec)
      const y = H - 20 - (note.note - MIN_PITCH + 1) * noteHeight
      const h = Math.max(1, noteHeight - 1)

      if (x + w < pianoWidth || x > W) return

      ctx.fillStyle = note._temp ? '#6ee7b7' : '#34d399'
      ctx.fillRect(x, y, w, h)
      ctx.strokeStyle = '#ffffff'
      ctx.lineWidth = 1
      ctx.strokeRect(x, y, w, h)
    })

    ctx.restore()
  },

  handleHover(mx, my, clientX, clientY) {
    const notes = this.parseNotes()
    const rect = this.canvas.getBoundingClientRect()
    const W = rect.width
    const H = rect.height
    const pianoWidth = 40
    const pitchRange = MAX_PITCH - MIN_PITCH
    const noteHeight = (H - 20) / pitchRange
    const maxTime = notes.length > 0 ? Math.max(...notes.map(n => n.offset)) + 1 : 1
    const pxPerSec = ((W - pianoWidth) / maxTime) * this.zoom

    let found = null
    notes.forEach((note, idx) => {
      const x = pianoWidth + note.onset * pxPerSec - this.scrollOffset
      const w = Math.max(2, (note.offset - note.onset) * pxPerSec)
      const y = H - 20 - (note.note - MIN_PITCH + 1) * noteHeight
      const h = Math.max(1, noteHeight - 1)

      if (mx >= x && mx <= x + w && my >= y && my <= y + h) {
        found = idx
      }
    })

    if (found !== null) {
      const note = notes[found]
      const dur = (note.offset - note.onset).toFixed(3)
      this.tooltip.textContent = `${pitchToName(note.note)} | vel: ${note.velocity.toFixed(2)} | ${dur}s`
      this.tooltip.style.left = `${mx + 12}px`
      this.tooltip.style.top = `${my - 24}px`
      this.tooltip.classList.remove('hidden')
    } else {
      this.tooltip.classList.add('hidden')
    }

    if (this.hoveredNote !== found) {
      this.hoveredNote = found
      this.draw()
    }
  }
}

export default PianoRoll
