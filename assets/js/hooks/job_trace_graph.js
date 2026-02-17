import * as d3 from "d3"

/**
 * JobTraceGraph - D3.js dependency graph for the worker pipeline.
 * Shows Download -> Processing -> Analysis with status coloring.
 */
const JobTraceGraph = {
  mounted() {
    this.handleEvent("job_trace_graph", ({ nodes, links }) => {
      this.renderGraph(nodes, links)
    })
  },

  renderGraph(nodes, links) {
    const el = this.el
    el.innerHTML = ""

    const width = el.clientWidth || 320
    const height = 160

    const svg = d3.select(el)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)

    const statusColor = (status) => {
      switch (status) {
        case "completed": return "#22c55e"
        case "executing":
        case "available": return "#3b82f6"
        case "discarded":
        case "cancelled": return "#ef4444"
        case "retryable": return "#f59e0b"
        default: return "#6b7280"
      }
    }

    // Position nodes horizontally
    const xScale = d3.scalePoint()
      .domain(nodes.map(n => n.id))
      .range([60, width - 60])
      .padding(0.5)

    const yCenter = height / 2

    // Draw links (arrows)
    svg.selectAll("line")
      .data(links)
      .join("line")
      .attr("x1", d => xScale(d.source))
      .attr("y1", yCenter)
      .attr("x2", d => xScale(d.target))
      .attr("y2", yCenter)
      .attr("stroke", "#4b5563")
      .attr("stroke-width", 2)
      .attr("marker-end", "url(#arrow)")

    // Arrow marker
    svg.append("defs").append("marker")
      .attr("id", "arrow")
      .attr("viewBox", "0 0 10 10")
      .attr("refX", 25)
      .attr("refY", 5)
      .attr("markerWidth", 6)
      .attr("markerHeight", 6)
      .attr("orient", "auto")
      .append("path")
      .attr("d", "M 0 0 L 10 5 L 0 10 z")
      .attr("fill", "#4b5563")

    // Draw nodes
    const nodeGroup = svg.selectAll("g.node")
      .data(nodes)
      .join("g")
      .attr("class", "node")
      .attr("transform", d => `translate(${xScale(d.id)}, ${yCenter})`)

    nodeGroup.append("circle")
      .attr("r", 20)
      .attr("fill", d => statusColor(d.status))
      .attr("stroke", "#1f2937")
      .attr("stroke-width", 2)

    nodeGroup.append("text")
      .attr("text-anchor", "middle")
      .attr("dy", 35)
      .attr("fill", "#9ca3af")
      .attr("font-size", "10px")
      .text(d => d.label.replace("Worker", ""))

    // Tooltip on hover for errors
    nodeGroup.append("title")
      .text(d => d.error ? `Error: ${d.error}` : d.status)
  }
}

export default JobTraceGraph
