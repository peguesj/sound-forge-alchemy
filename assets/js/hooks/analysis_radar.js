/**
 * AnalysisRadar Hook - Radar/spider chart for primary audio features
 * 6 axes: Tempo, Energy, Brightness, Richness, ZCR, Flatness
 */
import * as d3 from "d3"

const AnalysisRadar = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.features
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    const axes = [
      { key: "tempo", label: "Tempo", value: Math.min((data.tempo || 0) / 200, 1) },
      { key: "energy", label: "Energy", value: Math.min(data.energy || 0, 1) },
      { key: "brightness", label: "Brightness", value: Math.min((data.spectral_centroid || 0) / 8000, 1) },
      { key: "richness", label: "Richness", value: Math.min((data.spectral_bandwidth || data.spectral_rolloff || 0) / 4000, 1) },
      { key: "zcr", label: "ZCR", value: Math.min((data.zero_crossing_rate || 0) / 0.2, 1) },
      { key: "flatness", label: "Flatness", value: Math.min((data.spectral_flatness || 0) / 0.5, 1) }
    ]

    const width = 280
    const height = 280
    const margin = 40
    const radius = Math.min(width, height) / 2 - margin
    const levels = 4
    const total = axes.length
    const angleSlice = (Math.PI * 2) / total

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${width / 2},${height / 2})`)

    // Background circles
    for (let level = 1; level <= levels; level++) {
      const r = (radius / levels) * level
      svg.append("circle")
        .attr("r", r)
        .attr("fill", "none")
        .attr("stroke", "#374151")
        .attr("stroke-width", 0.5)
    }

    // Axis lines and labels
    axes.forEach((axis, i) => {
      const angle = angleSlice * i - Math.PI / 2
      const x = Math.cos(angle) * radius
      const y = Math.sin(angle) * radius

      svg.append("line")
        .attr("x1", 0).attr("y1", 0)
        .attr("x2", x).attr("y2", y)
        .attr("stroke", "#4b5563")
        .attr("stroke-width", 0.5)

      const labelX = Math.cos(angle) * (radius + 18)
      const labelY = Math.sin(angle) * (radius + 18)

      svg.append("text")
        .attr("x", labelX)
        .attr("y", labelY)
        .attr("text-anchor", "middle")
        .attr("dominant-baseline", "middle")
        .attr("fill", "#9ca3af")
        .attr("font-size", "10px")
        .text(axis.label)
    })

    // Data polygon
    const points = axes.map((axis, i) => {
      const angle = angleSlice * i - Math.PI / 2
      const r = axis.value * radius
      return [Math.cos(angle) * r, Math.sin(angle) * r]
    })

    const lineGen = d3.line().curve(d3.curveLinearClosed)

    // Gradient fill
    const defs = svg.append("defs")
    const gradient = defs.append("radialGradient")
      .attr("id", "radar-gradient")
    gradient.append("stop").attr("offset", "0%").attr("stop-color", "#a855f7").attr("stop-opacity", 0.4)
    gradient.append("stop").attr("offset", "100%").attr("stop-color", "#7c3aed").attr("stop-opacity", 0.1)

    svg.append("path")
      .attr("d", lineGen(points))
      .attr("fill", "url(#radar-gradient)")
      .attr("stroke", "#a855f7")
      .attr("stroke-width", 2)

    // Data points
    points.forEach(([x, y]) => {
      svg.append("circle")
        .attr("cx", x).attr("cy", y)
        .attr("r", 3)
        .attr("fill", "#c084fc")
    })
  }
}

export default AnalysisRadar
