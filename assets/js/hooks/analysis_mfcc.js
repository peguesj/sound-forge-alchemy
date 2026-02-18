/**
 * AnalysisMFCC Hook - MFCC coefficient bar chart
 * 13 horizontal bars with gradient coloring and variance error bars
 */
import * as d3 from "d3"

const AnalysisMFCC = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const raw = this.el.dataset.mfcc
    if (!raw) return

    let data
    try {
      data = JSON.parse(raw)
    } catch {
      return
    }

    const means = data.means || []
    const variances = data.variances || []
    if (means.length === 0) return

    const width = 280
    const height = 260
    const margin = { top: 10, right: 20, bottom: 20, left: 55 }
    const innerW = width - margin.left - margin.right
    const innerH = height - margin.top - margin.bottom

    this.el.innerHTML = ""

    const svg = d3.select(this.el)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("class", "w-full h-auto")
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    const labels = means.map((_, i) => `MFCC ${i + 1}`)

    const yScale = d3.scaleBand()
      .domain(labels)
      .range([0, innerH])
      .padding(0.15)

    // Normalize means for display -- use absolute value extents
    const maxAbs = Math.max(...means.map(Math.abs), 1)
    const xScale = d3.scaleLinear()
      .domain([-maxAbs, maxAbs])
      .range([0, innerW])

    const colorScale = d3.scaleSequential(d3.interpolatePurples)
      .domain([0, means.length])

    // Bars
    means.forEach((val, i) => {
      const barStart = Math.min(xScale(0), xScale(val))
      const barWidth = Math.abs(xScale(val) - xScale(0))

      svg.append("rect")
        .attr("x", barStart)
        .attr("y", yScale(labels[i]))
        .attr("width", barWidth)
        .attr("height", yScale.bandwidth())
        .attr("fill", colorScale(i))
        .attr("rx", 2)

      // Variance error bar
      if (variances[i] && variances[i] > 0) {
        const stddev = Math.sqrt(variances[i])
        const errLeft = xScale(val - stddev)
        const errRight = xScale(val + stddev)
        const centerY = yScale(labels[i]) + yScale.bandwidth() / 2

        svg.append("line")
          .attr("x1", Math.max(0, errLeft))
          .attr("x2", Math.min(innerW, errRight))
          .attr("y1", centerY)
          .attr("y2", centerY)
          .attr("stroke", "#9ca3af")
          .attr("stroke-width", 1)
          .attr("opacity", 0.5)
      }
    })

    // Zero line
    svg.append("line")
      .attr("x1", xScale(0))
      .attr("x2", xScale(0))
      .attr("y1", 0)
      .attr("y2", innerH)
      .attr("stroke", "#4b5563")
      .attr("stroke-width", 0.5)

    // Y axis labels
    svg.append("g")
      .call(d3.axisLeft(yScale).tickSize(0))
      .selectAll("text")
      .attr("fill", "#9ca3af")
      .attr("font-size", "8px")

    svg.selectAll(".domain").attr("stroke", "none")
  }
}

export default AnalysisMFCC
