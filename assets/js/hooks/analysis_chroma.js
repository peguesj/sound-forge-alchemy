/**
 * AnalysisChroma Hook - Circular pitch class distribution wheel
 * 12 segments for pitch classes (C through B)
 */
import * as d3 from "d3"

const PITCH_CLASSES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

const AnalysisChroma = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.chroma
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    const detectedKey = this.el.dataset.detectedKey || ""
    const chromaValues = data.stft || data.cqt || data.cens || []
    if (chromaValues.length !== 12) return

    const width = 280
    const height = 280
    const outerRadius = 110
    const innerRadius = 40
    const angleStep = (Math.PI * 2) / 12

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${width / 2},${height / 2})`)

    const colorScale = d3.scaleSequential(d3.interpolatePurples).domain([0, 1])

    const arc = d3.arc()
      .innerRadius(innerRadius)
      .outerRadius(outerRadius)

    // Normalize chroma to 0-1
    const maxVal = Math.max(...chromaValues, 0.001)

    chromaValues.forEach((val, i) => {
      const startAngle = angleStep * i - Math.PI / 2
      const endAngle = startAngle + angleStep

      const normalized = val / maxVal
      const isKey = detectedKey.startsWith(PITCH_CLASSES[i])

      svg.append("path")
        .attr("d", arc({ startAngle, endAngle }))
        .attr("fill", colorScale(normalized))
        .attr("stroke", isKey ? "#c084fc" : "#1f2937")
        .attr("stroke-width", isKey ? 2 : 0.5)
        .attr("opacity", 0.3 + normalized * 0.7)

      // Labels
      const labelAngle = (startAngle + endAngle) / 2
      const labelR = outerRadius + 16
      const lx = Math.cos(labelAngle) * labelR
      const ly = Math.sin(labelAngle) * labelR

      svg.append("text")
        .attr("x", lx)
        .attr("y", ly)
        .attr("text-anchor", "middle")
        .attr("dominant-baseline", "middle")
        .attr("fill", isKey ? "#c084fc" : "#9ca3af")
        .attr("font-size", isKey ? "11px" : "9px")
        .attr("font-weight", isKey ? "bold" : "normal")
        .text(PITCH_CLASSES[i])
    })

    // If we have multiple chroma types, draw concentric rings
    const chromaTypes = [
      { key: "stft", label: "STFT" },
      { key: "cqt", label: "CQT" },
      { key: "cens", label: "CENS" }
    ].filter(t => data[t.key] && data[t.key].length === 12)

    if (chromaTypes.length > 1) {
      const ringWidth = (outerRadius - innerRadius) / chromaTypes.length

      chromaTypes.forEach((type, ringIdx) => {
        const ringInner = innerRadius + ringWidth * ringIdx
        const ringOuter = ringInner + ringWidth
        const ringArc = d3.arc().innerRadius(ringInner).outerRadius(ringOuter)
        const vals = data[type.key]
        const rMax = Math.max(...vals, 0.001)

        vals.forEach((val, i) => {
          const startAngle = angleStep * i - Math.PI / 2
          const endAngle = startAngle + angleStep
          const norm = val / rMax

          svg.append("path")
            .attr("d", ringArc({ startAngle, endAngle }))
            .attr("fill", colorScale(norm))
            .attr("stroke", "#1f2937")
            .attr("stroke-width", 0.3)
            .attr("opacity", 0.3 + norm * 0.7)
        })
      })
    }

    // Center text
    svg.append("text")
      .attr("text-anchor", "middle")
      .attr("dominant-baseline", "middle")
      .attr("fill", "#c084fc")
      .attr("font-size", "14px")
      .attr("font-weight", "bold")
      .text(detectedKey || "?")
  }
}

export default AnalysisChroma
