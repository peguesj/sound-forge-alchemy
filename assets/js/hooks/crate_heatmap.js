/**
 * CrateHeatmap — D3.js similarity matrix heatmap hook.
 *
 * Attributes on the element:
 *   data-tracks  JSON array of track name strings  e.g. '["Track A","Track B"]'
 *   data-matrix  JSON NxN float matrix             e.g. '[[1,0.8],[0.8,1]]'
 *
 * Color scale: gray #374151 (0.0) → purple #7c3aed (1.0)
 */
const CrateHeatmap = {
  mounted() {
    this._render();
  },

  updated() {
    this._render();
  },

  _render() {
    const el = this.el;
    el.innerHTML = "";

    let tracks, matrix;
    try {
      tracks = JSON.parse(el.dataset.tracks || "[]");
      matrix = JSON.parse(el.dataset.matrix || "[]");
    } catch (_) {
      el.innerHTML = '<p class="text-gray-600 text-xs p-4">Invalid heatmap data</p>';
      return;
    }

    const n = tracks.length;
    if (n < 2) {
      el.innerHTML =
        '<p class="text-gray-500 text-xs p-4 text-center">Load at least 2 analyzed tracks to see similarity heatmap</p>';
      return;
    }

    // Dimensions
    const labelWidth = 90;
    const cellSize = Math.min(28, Math.floor((el.clientWidth - labelWidth - 20) / n));
    const width = labelWidth + cellSize * n + 20;
    const height = labelWidth + cellSize * n + 20;

    const svg = d3
      .select(el)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .style("overflow", "visible");

    // Color scale
    const colorScale = d3
      .scaleLinear()
      .domain([0, 0.5, 1])
      .range(["#374151", "#5b21b6", "#7c3aed"]);

    const g = svg.append("g").attr("transform", `translate(${labelWidth},${labelWidth})`);

    // Row labels (left)
    svg
      .selectAll(".row-label")
      .data(tracks)
      .enter()
      .append("text")
      .attr("class", "row-label")
      .attr("x", labelWidth - 4)
      .attr("y", (_, i) => labelWidth + i * cellSize + cellSize / 2 + 4)
      .attr("text-anchor", "end")
      .attr("fill", "#9ca3af")
      .attr("font-size", "9px")
      .attr("font-family", "monospace")
      .text((d) => (d.length > 14 ? d.slice(0, 13) + "…" : d));

    // Col labels (top, rotated)
    svg
      .selectAll(".col-label")
      .data(tracks)
      .enter()
      .append("text")
      .attr("class", "col-label")
      .attr("transform", (_, i) => {
        const x = labelWidth + i * cellSize + cellSize / 2;
        const y = labelWidth - 4;
        return `translate(${x},${y}) rotate(-45)`;
      })
      .attr("text-anchor", "start")
      .attr("fill", "#9ca3af")
      .attr("font-size", "9px")
      .attr("font-family", "monospace")
      .text((d) => (d.length > 14 ? d.slice(0, 13) + "…" : d));

    // Tooltip
    const tooltip = d3
      .select(el)
      .append("div")
      .style("position", "absolute")
      .style("background", "#1f2937")
      .style("border", "1px solid #374151")
      .style("color", "#e5e7eb")
      .style("padding", "4px 8px")
      .style("border-radius", "4px")
      .style("font-size", "10px")
      .style("pointer-events", "none")
      .style("opacity", "0")
      .style("z-index", "100")
      .style("white-space", "nowrap");

    // Cells
    matrix.forEach((row, ri) => {
      row.forEach((val, ci) => {
        g.append("rect")
          .attr("x", ci * cellSize)
          .attr("y", ri * cellSize)
          .attr("width", cellSize - 1)
          .attr("height", cellSize - 1)
          .attr("rx", 2)
          .attr("fill", colorScale(val))
          .style("cursor", "default")
          .on("mouseenter", function (event) {
            const score = Math.round(val * 100) / 100;
            tooltip
              .html(`${tracks[ri]} × ${tracks[ci]}: <b>${score}</b>`)
              .style("opacity", "1")
              .style("left", event.offsetX + 12 + "px")
              .style("top", event.offsetY - 24 + "px");
            d3.select(this).attr("stroke", "#a78bfa").attr("stroke-width", 1.5);
          })
          .on("mouseleave", function () {
            tooltip.style("opacity", "0");
            d3.select(this).attr("stroke", null);
          });

        // Score text for larger cells
        if (cellSize >= 24) {
          g.append("text")
            .attr("x", ci * cellSize + cellSize / 2)
            .attr("y", ri * cellSize + cellSize / 2 + 3)
            .attr("text-anchor", "middle")
            .attr("fill", val > 0.5 ? "#f3f4f6" : "#6b7280")
            .attr("font-size", "8px")
            .text(Math.round(val * 10) / 10);
        }
      });
    });

    // Color legend
    const legendWidth = Math.min(120, n * cellSize);
    const legendG = svg
      .append("g")
      .attr("transform", `translate(${labelWidth}, ${height - 14})`);

    const defs = svg.append("defs");
    const grad = defs
      .append("linearGradient")
      .attr("id", "heatmap-grad-" + el.id);
    grad.append("stop").attr("offset", "0%").attr("stop-color", "#374151");
    grad.append("stop").attr("offset", "50%").attr("stop-color", "#5b21b6");
    grad.append("stop").attr("offset", "100%").attr("stop-color", "#7c3aed");

    legendG
      .append("rect")
      .attr("width", legendWidth)
      .attr("height", 6)
      .attr("rx", 3)
      .attr("fill", `url(#heatmap-grad-${el.id})`);

    legendG
      .append("text")
      .attr("x", 0)
      .attr("y", -2)
      .attr("fill", "#6b7280")
      .attr("font-size", "8px")
      .text("0 (dissimilar)");

    legendG
      .append("text")
      .attr("x", legendWidth)
      .attr("y", -2)
      .attr("text-anchor", "end")
      .attr("fill", "#a78bfa")
      .attr("font-size", "8px")
      .text("1 (compatible)");
  },
};

export default CrateHeatmap;
