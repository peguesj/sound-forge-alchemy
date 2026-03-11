/**
 * ChordProgression Hook - D3-based chord timeline visualization
 * Renders detected chords as colored blocks on a horizontal timeline.
 */
import * as d3 from "d3"

const CHORD_COLORS = {
  'maj': '#3b82f6',  // blue
  'min': '#8b5cf6',  // purple
  'dim': '#ef4444',  // red
  'aug': '#f97316',  // orange
  '7':   '#22c55e',  // green
  'maj7': '#06b6d4', // cyan
  'min7': '#a855f7', // violet
}

function getChordQuality(chord) {
  if (chord.endsWith('min7') || chord.endsWith('m7')) return 'min7'
  if (chord.endsWith('maj7') || chord.endsWith('M7')) return 'maj7'
  if (chord.endsWith('dim')) return 'dim'
  if (chord.endsWith('aug')) return 'aug'
  if (chord.endsWith('7')) return '7'
  if (chord.endsWith('m')) return 'min'
  return 'maj'
}

function getChordColor(chord) {
  const quality = getChordQuality(chord)
  return CHORD_COLORS[quality] || '#6b7280'
}

const ChordProgression = {
  mounted() {
    this.playbackPosition = 0
    this.draw()

    // Listen for playback position updates
    this.handleEvent("playback_position", ({position}) => {
      this.playbackPosition = position
      this.updatePlayhead()
    })
  },

  updated() {
    this.draw()
  },

  parseData() {
    const raw = this.el.dataset.chords
    if (!raw) return { chords: [], key: null }
    try {
      return JSON.parse(raw)
    } catch {
      return { chords: [], key: null }
    }
  },

  draw() {
    const { chords, key } = this.parseData()
    this.el.innerHTML = ''

    const containerWidth = this.el.clientWidth || 600
    const height = 80
    const margin = { top: 24, right: 10, bottom: 20, left: 10 }
    const width = containerWidth - margin.left - margin.right
    const chartHeight = height - margin.top - margin.bottom

    if (chords.length === 0) {
      const div = document.createElement('div')
      div.className = 'text-gray-500 text-sm text-center py-4'
      div.textContent = 'No chord data'
      this.el.appendChild(div)
      return
    }

    const maxTime = Math.max(...chords.map(c => c.end))

    const svg = d3.select(this.el)
      .append('svg')
      .attr('viewBox', `0 0 ${containerWidth} ${height}`)
      .attr('class', 'w-full h-auto')

    const g = svg.append('g')
      .attr('transform', `translate(${margin.left},${margin.top})`)

    const xScale = d3.scaleLinear().domain([0, maxTime]).range([0, width])

    // Key label
    if (key) {
      svg.append('text')
        .attr('x', margin.left)
        .attr('y', 16)
        .attr('fill', '#d1d5db')
        .attr('font-size', '12px')
        .attr('font-weight', 'bold')
        .text(`Key: ${key}`)
    }

    // Chord blocks
    g.selectAll('rect.chord')
      .data(chords)
      .join('rect')
      .attr('class', 'chord')
      .attr('x', d => xScale(d.start))
      .attr('y', 0)
      .attr('width', d => Math.max(2, xScale(d.end) - xScale(d.start) - 1))
      .attr('height', chartHeight)
      .attr('fill', d => getChordColor(d.chord))
      .attr('opacity', d => 0.4 + d.confidence * 0.5)
      .attr('rx', 2)

    // Chord labels
    g.selectAll('text.chord-label')
      .data(chords)
      .join('text')
      .attr('class', 'chord-label')
      .attr('x', d => xScale(d.start) + (xScale(d.end) - xScale(d.start)) / 2)
      .attr('y', chartHeight / 2 + 4)
      .attr('text-anchor', 'middle')
      .attr('fill', '#f9fafb')
      .attr('font-size', d => {
        const blockWidth = xScale(d.end) - xScale(d.start)
        return blockWidth > 30 ? '10px' : '8px'
      })
      .text(d => {
        const blockWidth = xScale(d.end) - xScale(d.start)
        return blockWidth > 20 ? d.chord : ''
      })

    // Time axis
    const tickCount = Math.min(10, Math.floor(maxTime))
    const xAxis = d3.axisBottom(xScale)
      .ticks(tickCount)
      .tickFormat(d => `${d}s`)

    g.append('g')
      .attr('transform', `translate(0,${chartHeight})`)
      .call(xAxis)
      .selectAll('text')
      .attr('fill', '#9ca3af')
      .attr('font-size', '9px')

    g.selectAll('.domain, .tick line')
      .attr('stroke', '#4b5563')

    // Playhead
    this.playheadLine = g.append('line')
      .attr('class', 'playhead')
      .attr('x1', 0).attr('x2', 0)
      .attr('y1', 0).attr('y2', chartHeight)
      .attr('stroke', '#ef4444')
      .attr('stroke-width', 2)
      .attr('opacity', 0)

    this.xScale = xScale
  },

  updatePlayhead() {
    if (!this.playheadLine || !this.xScale) return
    const x = this.xScale(this.playbackPosition)
    this.playheadLine
      .attr('x1', x).attr('x2', x)
      .attr('opacity', 1)
  }
}

export default ChordProgression
