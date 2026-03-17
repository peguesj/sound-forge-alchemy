/**
 * DrumGraph Hook — XO-style 2D scatter of drum events by time + category
 *
 * Renders a D3-force scatter plot where:
 *   - X axis: time_s (position in track)
 *   - Y axis: jittered by drum category
 *   - Color: drum category (kick/snare/hihat/clap/perc)
 *   - Radius: proportional to confidence
 *   - Hover: shows category + time + confidence
 */
import * as d3 from "d3"

const CATEGORY_Y = { kick: 0.85, snare: 0.65, hihat: 0.45, clap: 0.3, perc: 0.15 }
const CATEGORY_COLORS = {
  kick: "#ef4444",
  snare: "#eab308",
  hihat: "#06b6d4",
  clap: "#a855f7",
  perc: "#6b7280"
}

const DrumGraph = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.drumEvents
    if (!raw) return

    let events = []
    try { events = JSON.parse(raw) } catch { return }
    if (!events.length) return

    const width = this.el.clientWidth || 560
    const height = parseInt(this.el.style.height) || 200
    const margin = { top: 12, right: 16, bottom: 24, left: 44 }
    const innerW = width - margin.left - margin.right
    const innerH = height - margin.top - margin.bottom

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const maxTime = d3.max(events, d => d.time_s) || 1
    const xScale = d3.scaleLinear().domain([0, maxTime]).range([0, innerW])
    const yScale = d3.scaleLinear().domain([0, 1]).range([innerH, 0])

    // Gridlines
    svg.append("g")
      .attr("class", "grid")
      .selectAll("line")
      .data(Object.keys(CATEGORY_Y))
      .enter()
      .append("line")
      .attr("x1", 0).attr("x2", innerW)
      .attr("y1", d => yScale(CATEGORY_Y[d]))
      .attr("y2", d => yScale(CATEGORY_Y[d]))
      .attr("stroke", d => CATEGORY_COLORS[d])
      .attr("stroke-opacity", 0.15)
      .attr("stroke-dasharray", "3,3")

    // Category labels on Y axis
    Object.entries(CATEGORY_Y).forEach(([cat, y]) => {
      svg.append("text")
        .attr("x", -6)
        .attr("y", yScale(y) + 4)
        .attr("text-anchor", "end")
        .attr("fill", CATEGORY_COLORS[cat])
        .attr("font-size", "9px")
        .attr("font-weight", "500")
        .text(cat)
    })

    // Event dots with jitter
    const jitter = d3.randomNormal(0, 0.025)

    svg.selectAll("circle.drum-event")
      .data(events)
      .enter()
      .append("circle")
      .attr("class", "drum-event")
      .attr("cx", d => xScale(d.time_s))
      .attr("cy", d => {
        const base = CATEGORY_Y[d.category] || 0.5
        return yScale(Math.max(0, Math.min(1, base + jitter())))
      })
      .attr("r", d => 2.5 + (d.confidence || 0.5) * 3)
      .attr("fill", d => CATEGORY_COLORS[d.category] || "#9ca3af")
      .attr("fill-opacity", 0.75)
      .attr("cursor", "pointer")
      .append("title")
      .text(d => `${d.category} @ ${d.time_s.toFixed(2)}s (${Math.round((d.confidence || 0) * 100)}%)`)

    // X axis
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
      .attr("font-size", "8px")

    svg.selectAll(".domain, .tick line").attr("stroke", "#374151")
  }
}

export default DrumGraph
