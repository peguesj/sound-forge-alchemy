/**
 * AnalysisStructure Hook - Song structure timeline visualization
 * Horizontal SVG timeline with color-coded section rectangles (verse, chorus, bridge, etc.)
 * Clickable segments push a seek_to event with position_ms.
 */

const AnalysisStructure = {
  mounted() {
    this.renderStructure();
    this.observer = new ResizeObserver(() => this.renderStructure());
    this.observer.observe(this.el);
  },

  updated() {
    this.renderStructure();
  },

  destroyed() {
    if (this.observer) this.observer.disconnect();
  },

  renderStructure() {
    const segmentsRaw = this.el.dataset.segments;
    if (!segmentsRaw) {
      this.el.innerHTML = '<p class="text-gray-500 text-sm italic">No structure data available</p>';
      return;
    }

    let segments;
    try {
      segments = JSON.parse(segmentsRaw);
    } catch (e) {
      this.el.innerHTML = '<p class="text-red-500 text-sm">Error parsing structure data</p>';
      return;
    }

    if (!segments || segments.length === 0) {
      this.el.innerHTML = '<p class="text-gray-500 text-sm italic">No structure data available</p>';
      return;
    }

    const width = this.el.clientWidth || 600;
    const height = 60;
    const labelHeight = 20;
    const totalHeight = height + labelHeight;
    const totalDuration = segments[segments.length - 1].end_time - segments[0].start_time;

    if (totalDuration <= 0) return;

    const colorMap = {
      intro: '#6b7280',      // gray-500
      outro: '#6b7280',
      verse: '#3b82f6',      // blue-500
      pre_chorus: '#eab308', // yellow-500
      chorus: '#a855f7',     // purple-500
      bridge: '#22c55e',     // green-500
      drop: '#ef4444',       // red-500
      breakdown: '#06b6d4',  // cyan-500
      build_up: '#f97316',   // orange-500
      other: '#9ca3af'       // gray-400
    };

    const startOffset = segments[0].start_time;

    let svg = `<svg width="${width}" height="${totalHeight}" xmlns="http://www.w3.org/2000/svg">`;

    // Tooltip container
    svg += '<style>';
    svg += '.seg-rect { cursor: pointer; transition: opacity 0.15s; }';
    svg += '.seg-rect:hover { opacity: 0.8; }';
    svg += '.seg-label { font-size: 10px; fill: #d1d5db; pointer-events: none; }';
    svg += '</style>';

    segments.forEach((seg, i) => {
      const x = ((seg.start_time - startOffset) / totalDuration) * width;
      const w = ((seg.end_time - seg.start_time) / totalDuration) * width;
      const color = colorMap[seg.section_type] || colorMap.other;
      const label = seg.label || seg.section_type;

      // Section rectangle
      svg += `<rect class="seg-rect" x="${x}" y="0" width="${Math.max(w, 1)}" height="${height}" fill="${color}" rx="2" `;
      svg += `data-start="${Math.round(seg.start_time * 1000)}" `;
      svg += `data-type="${seg.section_type}" data-label="${label}" `;
      svg += `data-energy="${(seg.energy_profile || 0).toFixed(2)}" `;
      svg += `data-confidence="${(seg.confidence || 0).toFixed(2)}" `;
      svg += `data-start-time="${seg.start_time.toFixed(1)}s" `;
      svg += `data-end-time="${seg.end_time.toFixed(1)}s">`;
      svg += `<title>${label} (${seg.start_time.toFixed(1)}s - ${seg.end_time.toFixed(1)}s)\nEnergy: ${(seg.energy_profile || 0).toFixed(2)} | Confidence: ${(seg.confidence || 0).toFixed(2)}</title>`;
      svg += '</rect>';

      // Label (only if wide enough)
      if (w > 30) {
        const textX = x + w / 2;
        svg += `<text class="seg-label" x="${textX}" y="${height / 2 + 4}" text-anchor="middle">${label}</text>`;
      }

      // Time label below
      if (w > 40) {
        const mins = Math.floor(seg.start_time / 60);
        const secs = Math.floor(seg.start_time % 60);
        const timeStr = `${mins}:${secs.toString().padStart(2, '0')}`;
        svg += `<text class="seg-label" x="${x + 2}" y="${height + 14}" text-anchor="start">${timeStr}</text>`;
      }
    });

    svg += '</svg>';
    this.el.innerHTML = svg;

    // Add click handlers for seek
    this.el.querySelectorAll('.seg-rect').forEach(rect => {
      rect.addEventListener('click', (e) => {
        const startMs = parseInt(e.target.dataset.start, 10);
        this.pushEvent('seek_to', { position_ms: startMs });
      });
    });
  }
};

export default AnalysisStructure;
