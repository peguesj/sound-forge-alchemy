/**
 * AnalysisSpectral Hook - Spectral contrast heatmap
 * 7-band spectral contrast as colored cells with cool-to-hot color scale
 */
import * as d3 from "d3"

const BAND_LABELS = ["Sub-bass", "Bass", "Low-mid", "Mid", "Upper-mid", "Presence", "Brilliance"]

const AnalysisSpectral = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.spectral
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    const contrast = data.contrast || []
    const valleys = data.valleys || []
    if (contrast.length === 0) return

    const numBands = Math.min(contrast.length, 7)
    const width = 280
    const height = 200
    const margin = { top: 10, right: 20, bottom: 30, left: 75 }
    const innerW = width - margin.left - margin.right
    const innerH = height - margin.top - margin.bottom

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const labels = BAND_LABELS.slice(0, numBands)

    const yScale = d3.scaleBand()
      .domain(labels)
      .range([0, innerH])
      .padding(0.1)

    // Contrast values as single-column heatmap
    const maxContrast = Math.max(...contrast, 1)
    const colorScale = d3.scaleSequential(d3.interpolateInferno)
      .domain([0, maxContrast])

    const cellWidth = Math.min(innerW, 120)

    contrast.slice(0, numBands).forEach((val, i) => {
      // Main contrast cell
      svg.append("rect")
        .attr("x", 0)
        .attr("y", yScale(labels[i]))
        .attr("width", cellWidth)
        .attr("height", yScale.bandwidth())
        .attr("fill", colorScale(val))
        .attr("rx", 3)

      // Value text overlay
      svg.append("text")
        .attr("x", cellWidth / 2)
        .attr("y", yScale(labels[i]) + yScale.bandwidth() / 2)
        .attr("text-anchor", "middle")
        .attr("dominant-baseline", "middle")
        .attr("fill", val > maxContrast * 0.5 ? "#1f2937" : "#e5e7eb")
        .attr("font-size", "9px")
        .text(val.toFixed(1))

      // Valley indicator (smaller cell next to contrast)
      if (valleys[i] !== undefined) {
        const valleyScale = d3.scaleSequential(d3.interpolateBlues)
          .domain([0, Math.max(...valleys, 1)])

        svg.append("rect")
          .attr("x", cellWidth + 4)
          .attr("y", yScale(labels[i]))
          .attr("width", 20)
          .attr("height", yScale.bandwidth())
          .attr("fill", valleyScale(valleys[i]))
          .attr("rx", 2)
      }
    })

    // Y axis labels
    svg.append("g")
      .call(d3.axisLeft(yScale).tickSize(0))
      .selectAll("text")
      .attr("fill", "#9ca3af")
      .attr("font-size", "9px")

    svg.selectAll(".domain").attr("stroke", "none")

    // Legend
    svg.append("text")
      .attr("x", 0)
      .attr("y", innerH + 18)
      .attr("fill", "#6b7280")
      .attr("font-size", "8px")
      .text("Contrast (dB)")

    if (valleys.length > 0) {
      svg.append("text")
        .attr("x", cellWidth + 4)
        .attr("y", innerH + 18)
        .attr("fill", "#6b7280")
        .attr("font-size", "8px")
        .text("Valley")
    }
  }
}

export default AnalysisSpectral
