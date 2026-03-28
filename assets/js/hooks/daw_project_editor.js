/**
 * DawProjectEditor Hook - Multi-track timeline editor for DAW project view
 *
 * Renders a visual timeline of all project tracks with type-coded color bars.
 * Data is driven by server-assigned data attributes updated on each LiveView diff.
 *
 * Data attributes (set by DawProjectLive):
 *   data-project-id  - UUID of the active project (null if no project selected)
 *   data-tracks      - JSON array of track objects
 *   data-track-types - JSON map of track_id -> track_type string
 */

const DawProjectEditor = {
  mounted() {
    this.renderTimeline();
    this.handleEvent("project_updated", () => this.renderTimeline());
  },

  updated() {
    this.renderTimeline();
  },

  renderTimeline() {
    const tracks = JSON.parse(this.el.dataset.tracks || "[]");
    const trackTypes = JSON.parse(this.el.dataset.trackTypes || "{}");

    if (tracks.length === 0) {
      this.el.innerHTML = '<p class="text-gray-500 p-4 text-sm">Add tracks to begin arranging</p>';
      return;
    }

    const rows = tracks.map(track => {
      const type = trackTypes[track.id] || "unknown";
      const pattern = this.patternForType(type);
      const durationBar = track.duration_ms ? Math.min((track.duration_ms / 1000 / 300) * 100, 100) : 20;

      return `
        <div class="flex items-center gap-3 p-2 border-b border-gray-800 hover:bg-gray-800/50">
          <span class="text-gray-500 text-xs w-6 text-right">${track.position + 1}</span>
          <span class="text-gray-200 text-sm flex-none w-40 truncate">${track.title}</span>
          <div class="flex-1 h-8 bg-gray-800 rounded relative overflow-hidden">
            <div class="h-full ${pattern.bgClass} rounded" style="width: ${durationBar}%">
              ${pattern.decoration}
            </div>
          </div>
          <span class="text-xs text-gray-400 w-16 text-right">${this.formatDuration(track.duration_ms)}</span>
        </div>
      `;
    }).join("");

    this.el.innerHTML = `<div class="divide-y divide-gray-800">${rows}</div>`;
  },

  patternForType(type) {
    switch (type) {
      case "full_track":
        return { bgClass: "bg-blue-800/60", decoration: "" };
      case "loop":
        return { bgClass: "bg-green-800/60", decoration: '<span class="absolute right-1 top-1 text-xs text-green-400">&#x21BA;</span>' };
      case "drum_loop":
        return { bgClass: "bg-orange-800/60", decoration: '<span class="absolute right-1 top-1 text-xs text-orange-400">&#x25A6;</span>' };
      case "sample_loop":
        return { bgClass: "bg-yellow-800/60", decoration: '<span class="absolute right-1 top-1 text-xs text-yellow-400">&#x21BA;</span>' };
      default:
        return { bgClass: "bg-gray-700/60", decoration: "" };
    }
  },

  formatDuration(ms) {
    if (!ms) return "--:--";
    const s = Math.floor(ms / 1000);
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return `${m}:${rem.toString().padStart(2, "0")}`;
  },
};

export default DawProjectEditor;
