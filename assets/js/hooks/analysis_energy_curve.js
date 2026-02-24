/**
 * AnalysisEnergyCurve Hook - Energy curve visualization with arrangement markers overlay
 * Renders an SVG area chart of energy over time with marker annotations for
 * key changes, drops, build-ups, and energy shifts.
 *
 * Data attributes:
 *   data-energy-curve:        JSON { times: number[], values: number[] }
 *   data-arrangement-markers: JSON Array<{ position_ms, marker_type, description, intensity }>
 */
const AnalysisEnergyCurve = {
  mounted() {
    this.renderCurve();
    this.observer = new ResizeObserver(() => this.renderCurve());
    this.observer.observe(this.el);
  },

  updated() {
    this.renderCurve();
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
  },

  renderCurve() {
    const curveRaw = this.el.dataset.energyCurve;
    const markersRaw = this.el.dataset.arrangementMarkers;

    let curve = null, markers = [];
    try {
      if (curveRaw) curve = JSON.parse(curveRaw);
      if (markersRaw) markers = JSON.parse(markersRaw);
    } catch (e) {
      this.el.innerHTML = '<p class="text-red-500 text-sm">Error parsing energy data</p>';
      return;
    }

    if (!curve || !curve.times || !curve.values || curve.times.length === 0) {
      this.el.innerHTML = '<p class="text-gray-500 text-sm italic">No energy data available</p>';
      return;
    }

    const width = this.el.clientWidth || 600;
    const height = 100;
    const padding = { top: 10, bottom: 20, left: 0, right: 0 };
    const plotW = width - padding.left - padding.right;
    const plotH = height - padding.top - padding.bottom;

    const times = curve.times;
    const values = curve.values;
    const maxTime = times[times.length - 1];
    const maxVal = Math.max(...values) || 1;

    // Build SVG
    let svg = `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">`;

    // Gradient definition
    svg += '<defs>';
    svg += '<linearGradient id="energyGrad" x1="0" y1="1" x2="0" y2="0">';
    svg += '<stop offset="0%" stop-color="#3b82f6" stop-opacity="0.3"/>';
    svg += '<stop offset="40%" stop-color="#8b5cf6" stop-opacity="0.5"/>';
    svg += '<stop offset="80%" stop-color="#ef4444" stop-opacity="0.7"/>';
    svg += '<stop offset="100%" stop-color="#ef4444" stop-opacity="0.9"/>';
    svg += '</linearGradient>';
    svg += '</defs>';

    // Build area path
    let areaPath = `M ${padding.left} ${height - padding.bottom}`;
    for (let i = 0; i < times.length; i++) {
      const x = padding.left + (times[i] / maxTime) * plotW;
      const y = padding.top + plotH - (values[i] / maxVal) * plotH;
      areaPath += ` L ${x.toFixed(1)} ${y.toFixed(1)}`;
    }
    areaPath += ` L ${padding.left + plotW} ${height - padding.bottom} Z`;

    svg += `<path d="${areaPath}" fill="url(#energyGrad)" stroke="none"/>`;

    // Line on top of area
    let linePath = '';
    for (let i = 0; i < times.length; i++) {
      const x = padding.left + (times[i] / maxTime) * plotW;
      const y = padding.top + plotH - (values[i] / maxVal) * plotH;
      linePath += (i === 0 ? 'M' : ' L') + ` ${x.toFixed(1)} ${y.toFixed(1)}`;
    }
    svg += `<path d="${linePath}" fill="none" stroke="#a78bfa" stroke-width="1.5" opacity="0.8"/>`;

    // Arrangement markers
    const markerIcons = {
      key_change: '\u266B',    // musical note
      drop: '\u26A1',          // lightning bolt
      build_up: '\u25B2',      // up triangle
      energy_rise: '\u25B3',   // up triangle outline
      energy_drop: '\u25BD'    // down triangle outline
    };
    const markerColors = {
      key_change: '#eab308',
      drop: '#ef4444',
      build_up: '#f97316',
      energy_rise: '#22c55e',
      energy_drop: '#3b82f6'
    };

    markers.forEach(marker => {
      const posMs = marker.position_ms;
      const posSec = posMs / 1000;
      const x = padding.left + (posSec / maxTime) * plotW;
      const color = markerColors[marker.marker_type] || '#9ca3af';
      const icon = markerIcons[marker.marker_type] || '\u25CF';

      // Vertical line
      svg += `<line x1="${x}" y1="${padding.top}" x2="${x}" y2="${height - padding.bottom}" stroke="${color}" stroke-width="1" stroke-dasharray="3,3" opacity="0.7"/>`;

      // Icon
      svg += `<text x="${x}" y="${padding.top + 10}" text-anchor="middle" fill="${color}" font-size="12" style="cursor:pointer">`;
      svg += `${icon}<title>${marker.description || marker.marker_type} (${(posSec).toFixed(1)}s)\nIntensity: ${(marker.intensity || 0).toFixed(2)}</title>`;
      svg += '</text>';
    });

    // X-axis time labels
    const numLabels = Math.min(8, Math.floor(plotW / 60));
    for (let i = 0; i <= numLabels; i++) {
      const t = (i / numLabels) * maxTime;
      const x = padding.left + (t / maxTime) * plotW;
      const mins = Math.floor(t / 60);
      const secs = Math.floor(t % 60);
      svg += `<text x="${x}" y="${height - 2}" text-anchor="middle" fill="#6b7280" font-size="9">${mins}:${secs.toString().padStart(2, '0')}</text>`;
    }

    svg += '</svg>';
    this.el.innerHTML = svg;
  }
};

export default AnalysisEnergyCurve;
