/**
 * AnalysisBeats Hook - Beat timeline visualization
 * Horizontal SVG with vertical beat markers color-coded by regularity
 */
import * as d3 from "d3"

const AnalysisBeats = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.beats
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    const beats = data.times || []
    const tempo = data.tempo || 0
    if (beats.length < 2) return

    const width = 600
    const height = 80
    const margin = { top: 10, right: 20, bottom: 25, left: 20 }
    const innerW = width - margin.left - margin.right
    const innerH = height - margin.top - margin.bottom

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const xScale = d3.scaleLinear()
      .domain([0, beats[beats.length - 1]])
      .range([0, innerW])

    // Compute inter-beat intervals for color coding
    const expectedInterval = tempo > 0 ? 60 / tempo : 0
    const intervals = beats.slice(1).map((b, i) => b - beats[i])

    // Color based on deviation from expected interval
    const colorScale = d3.scaleSequential(d3.interpolateRdYlGn)
      .domain([0.3, 0]) // lower deviation = greener

    beats.forEach((beat, i) => {
      let deviation = 0
      if (expectedInterval > 0 && i > 0) {
        deviation = Math.abs(intervals[i - 1] - expectedInterval) / expectedInterval
      }

      svg.append("line")
        .attr("x1", xScale(beat))
        .attr("x2", xScale(beat))
        .attr("y1", 0)
        .attr("y2", innerH)
        .attr("stroke", i === 0 ? "#a855f7" : colorScale(Math.min(deviation, 0.3)))
        .attr("stroke-width", 1)
        .attr("opacity", 0.7)
    })

    // X axis (time)
    const xAxis = d3.axisBottom(xScale)
      .ticks(6)
      .tickFormat(d => {
        const m = Math.floor(d / 60)
        const s = Math.floor(d % 60)
        return `${m}:${String(s).padStart(2, "0")}`
      })

    svg.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(xAxis)
      .selectAll("text")
      .attr("fill", "#6b7280")
      .attr("font-size", "9px")

    svg.selectAll(".domain, .tick line").attr("stroke", "#374151")

    // Tempo annotation
    if (tempo > 0) {
      svg.append("text")
        .attr("x", innerW)
        .attr("y", -2)
        .attr("text-anchor", "end")
        .attr("fill", "#a855f7")
        .attr("font-size", "10px")
        .text(`${Math.round(tempo)} BPM`)
    }
  }
}

export default AnalysisBeats
