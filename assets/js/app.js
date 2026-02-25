// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/sound_forge"
import topbar from "../vendor/topbar"
import AudioPlayer from "./hooks/audio_player"
import AutoDismiss from "./hooks/auto_dismiss"
import ShiftSelect from "./hooks/shift_select"
import SpotifyPlayer from "./hooks/spotify_player"
import DebugLogScroll from "./hooks/debug_log_scroll"
import JobTraceGraph from "./hooks/job_trace_graph"
import AnalysisRadar from "./hooks/analysis_radar"
import AnalysisChroma from "./hooks/analysis_chroma"
import AnalysisBeats from "./hooks/analysis_beats"
import AnalysisMFCC from "./hooks/analysis_mfcc"
import AnalysisSpectral from "./hooks/analysis_spectral"
import AnalysisStructure from "./hooks/analysis_structure"
import AnalysisEnergyCurve from "./hooks/analysis_energy_curve"
import ResizeObserverHook from "./hooks/resize_observer_hook"
import SwipeHook from "./hooks/swipe_hook"
import StemMixerHook from "./hooks/stem_mixer_hook"
import PadAssignHook from "./hooks/pad_assign_hook"
import DawEditor from "./hooks/daw_editor"
import DawPreview from "./hooks/daw_preview"
import DjDeck from "./hooks/dj_deck"
import JogWheel from "./hooks/jog_wheel"
import ChromaticPads from "./hooks/chromatic_pads"
import TransportBar from "./hooks/transport_bar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {
  AudioPlayer, AutoDismiss, ShiftSelect, SpotifyPlayer,
  DebugLogScroll, JobTraceGraph,
  AnalysisRadar, AnalysisChroma, AnalysisBeats,
  AnalysisMFCC, AnalysisSpectral, AnalysisStructure, AnalysisEnergyCurve,
  ResizeObserverHook, SwipeHook, StemMixerHook, PadAssignHook, DawEditor, DawPreview, DjDeck, JogWheel, ChromaticPads, TransportBar,
  ...colocatedHooks
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Prevent Cmd+P / Ctrl+P from opening the browser print dialog;
// let the LiveView keydown handler switch to Pads view instead.
window.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "p") {
    e.preventDefault()
  }
})

// Accessibility: focus section headings on navigation
window.addEventListener("phx:focus_section_heading", (event) => {
  const section = event.detail.section
  // Small delay to allow the DOM to update after section switch
  requestAnimationFrame(() => {
    const heading = document.getElementById(`section-heading-${section}`)
    if (heading) heading.focus()
  })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

