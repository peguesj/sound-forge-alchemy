import Foundation
import SwiftUI

@MainActor
final class SFAAppModel: ObservableObject {
    @Published var selectedSection: NativeSection = .library
    @Published var runtime = BundleRuntimeStatus()
    @Published var processingEngines: [String] = BundledRuntimeCatalog.processingEngines
    @Published var capabilitySummary: String = "Loading bundled Swift capabilities"
    @Published var tracks: [TrackSummary] = []
    @Published var processingJobs: [LocalProcessingJob] = []
    @Published var cuePoints: [LocalCuePoint] = []
    @Published var deckSessions: [LocalDeckSession] = []
    @Published var performanceSets: [LocalPerformanceSet] = []
    @Published var dawProjects: [LocalDAWProject] = []
    @Published var dawTracks: [LocalDAWTrack] = []
    @Published var dawClips: [LocalDAWClip] = []
    @Published var editOperations: [LocalEditOperation] = []
    @Published var samplerBanks: [LocalSamplerBank] = []
    @Published var samplerPads: [LocalSamplerPad] = []
    @Published var samplePacks: [LocalSamplePack] = []
    @Published var padActions: [LocalPadAction] = []
    @Published var crates: [LocalCrate] = []
    @Published var crateTrackConfigs: [LocalCrateTrackConfig] = []
    @Published var bigLoopySets: [LocalBigLoopySet] = []
    @Published var controlProfiles: [LocalControlSurfaceProfile] = []
    @Published var controlMappings: [LocalControlMapping] = []
    @Published var agentDefinitions: [LocalAgentDefinition] = []
    @Published var agentPromptTemplates: [LocalAgentPromptTemplate] = []
    @Published var agentTools: [LocalAgentTool] = []
    @Published var agentTasks: [LocalAgentTask] = []
    @Published var agentRuns: [LocalAgentRun] = []
    @Published var llmProviders: [LocalLLMProvider] = []
    @Published var modelCapabilities: [LocalModelCapability] = []
    @Published var providerRoutes: [LocalProviderRoute] = []
    @Published var librarySummary = LocalLibrarySummary.empty
    @Published var localSettings = LocalAppSettings()
    @Published var secureTokenStatus: [LocalSecureTokenStatus] = []
    @Published var pipelineStages: [PipelineStage] = SFAAppModel.seedPipeline
    @Published var modules: [FeatureModule] = SFAAppModel.seedModules
    @Published var portDomains: [PortedDomain] = BundledRuntimeCatalog.seedPortDomains
    @Published var packagingReadiness: [PackagingReadinessItem] = []
    @Published var agents: [AgentSummary] = SFAAppModel.seedAgents
    @Published var runtimeEvents: [RuntimeEvent] = []
    @Published var importedFiles: [String] = []
    @Published var pmStories: [PMStory] = SFAAppModel.fallbackPMStories
    @Published var chatFocusRequest = UUID()

    let showcase = ShowcaseBridge()

    private let runtimeCatalog: BundledRuntimeCatalog
    private let libraryStore: LocalLibraryStore
    private let processingQueue: LocalProcessingQueue
    private var hasStarted = false

    init(
        runtimeCatalog: BundledRuntimeCatalog = BundledRuntimeCatalog(),
        libraryStore: LocalLibraryStore = LocalLibraryStore()
    ) {
        self.runtimeCatalog = runtimeCatalog
        self.libraryStore = libraryStore
        self.processingQueue = LocalProcessingQueue(store: libraryStore)
    }

    var repoRoot: URL {
        if let raw = ProcessInfo.processInfo.environment["SFA_PATH"], !raw.isEmpty {
            return URL(fileURLWithPath: raw)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer/sfa")
    }

    var nativeProgress: Double {
        let stories = pmStories
        guard !stories.isEmpty else { return 0 }
        return Double(stories.filter(\.passed).count) / Double(stories.count)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        appendEvent(source: "runtime", message: "Single-bundle Swift workbench started")
        loadPMPlan()
        loadLibraryDocument()
        refreshBundledRuntime()
        pushProgressCard()
    }

    func refreshBundledRuntime() {
        Task {
            let snapshot = await runtimeCatalog.loadSnapshot(repoRoot: repoRoot)
            runtime = snapshot.runtime
            processingEngines = snapshot.processingEngines
            capabilitySummary = snapshot.capabilitySummary
            portDomains = snapshot.portDomains
            packagingReadiness = snapshot.packagingReadiness
            appendEvent(
                source: "runtime",
                message: snapshot.runtime.message,
                detail: snapshot.runtime.storageURL.path
            )
            pushProgressCard()
        }
    }

    func select(section: NativeSection) {
        selectedSection = section
        appendEvent(source: "navigation", message: "Opened \(section.label)")
    }

    func handleImportedFiles(_ paths: [String]) {
        importedFiles = paths

        Task {
            do {
                let result = try await libraryStore.importAudio(paths: paths)
                applyLibraryDocument(result.document)
                let importedCount = result.inserted.count
                pipelineStages[0].state = importedCount > 0 ? .running : .ready
                pipelineStages[0].detail = importedCount > 0
                    ? "\(importedCount) file(s) persisted to local library"
                    : "Selected file(s) already exist in the local library"
                pipelineStages[0].progress = importedCount > 0 ? 0.35 : 1.0
                appendEvent(
                    source: "import",
                    message: importedCount > 0 ? "Persisted \(importedCount) audio file(s)" : "Import skipped duplicates",
                    detail: paths.joined(separator: ", ")
                )
                select(section: .pipeline)
                pushProgressCard()
            } catch {
                appendEvent(
                    source: "library.store",
                    level: "warning",
                    message: "Could not persist imported files",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func handlePlayback(_ command: PlaybackCommand) {
        appendEvent(source: "transport", message: command.rawValue)
    }

    func runPipelineAction(_ action: String) {
        appendEvent(source: "pipeline", message: action)
        switch action {
        case "refresh":
            refreshBundledRuntime()
        case "enqueue-stems":
            enqueueProcessing(kind: .stems)
        case "stem-separation":
            enqueueProcessing(kind: .stems)
        case "enqueue-analysis":
            enqueueProcessing(kind: .analysis)
        case "analyze-track":
            enqueueProcessing(kind: .analysis)
        case "enqueue-download":
            enqueueProcessing(kind: .download)
        case "enqueue-midi":
            enqueueProcessing(kind: .audioToMIDI)
        case "enqueue-chords":
            enqueueProcessing(kind: .chordDetection)
        case "enqueue-warp":
            enqueueProcessing(kind: .warp)
        case "enqueue-cleanup":
            enqueueProcessing(kind: .cleanup)
        case "enqueue-export":
            enqueueProcessing(kind: .export)
        case "run-ready":
            runReadyProcessingJobs()
        default:
            break
        }
        pushProgressCard()
    }

    func enqueueProcessing(kind: LocalProcessingJob.Kind) {
        Task {
            do {
                let result = try await processingQueue.enqueue(kind: kind)
                let plannedDocument = try await processingQueue.runPlanningPass(for: result.jobs)
                applyLibraryDocument(plannedDocument)
                let run = try await processingQueue.runReadyJobs(matching: result.jobs)
                applyLibraryDocument(run.document)
                appendEvent(
                    source: "processing.queue",
                    message: "Ran \(run.jobs.count) \(kind.label.lowercased()) job(s)",
                    detail: run.artifactURLs.isEmpty
                        ? "No artifacts generated"
                        : "Artifacts in \(run.artifactURLs[0].deletingLastPathComponent().path)"
                )
                select(section: .pipeline)
                pushProgressCard()
            } catch {
                appendEvent(
                    source: "processing.queue",
                    level: "warning",
                    message: "Could not queue \(kind.label.lowercased()) jobs",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func runReadyProcessingJobs() {
        Task {
            do {
                let run = try await processingQueue.runReadyJobs()
                applyLibraryDocument(run.document)
                appendEvent(
                    source: "processing.queue",
                    message: "Ran \(run.jobs.count) queued local job(s)",
                    detail: run.artifactURLs.isEmpty
                        ? "Queue had no runnable jobs"
                        : "Generated \(run.artifactURLs.count) artifact(s)"
                )
                select(section: .pipeline)
                pushProgressCard()
            } catch {
                appendEvent(
                    source: "processing.queue",
                    level: "warning",
                    message: "Could not run queued local jobs",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func runAgent(_ agentID: String) {
        Task {
            do {
                let result = try await libraryStore.runAgent(agentID: agentID)
                applyLibraryDocument(result.document)
                let provider = result.run.providerID ?? "local"
                appendEvent(
                    source: "agent.runtime",
                    message: "Ran \(result.run.agentID)",
                    detail: "\(provider) | \(result.run.model ?? "default model") | \(result.run.resultSummary)"
                )
                select(section: .agents)
                pushProgressCard()
            } catch {
                appendEvent(
                    source: "agent.runtime",
                    level: "warning",
                    message: "Could not run local agent",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func requestChatFocus() {
        chatFocusRequest = UUID()
        appendEvent(source: "showcase.chat", message: "Focused IPC chat composer")
    }

    func pushProgressCard() {
        guard showcase.isRunning else { return }

        let passed = pmStories.filter(\.passed).count
        let total = pmStories.count
        let body = "Swift port progress: \(passed)/\(total) PM stories passed. Current surface: \(selectedSection.label). Runtime: \(runtime.message)."
        showcase.pushCard(
            id: "native-upm-progress",
            title: "Single-Bundle Swift Port",
            body: body,
            kind: "progress",
            value: passed,
            max: total,
            items: pmStories.map { story in
                [
                    "id": story.id,
                    "title": "\(story.passed ? "passed" : "pending") - \(story.title)"
                ]
            }
        )
    }

    func appendEvent(source: String, level: String = "info", message: String, detail: String = "") {
        runtimeEvents.insert(
            RuntimeEvent(source: source, level: level, message: message, detail: detail),
            at: 0
        )
        if runtimeEvents.count > 80 {
            runtimeEvents.removeLast(runtimeEvents.count - 80)
        }
    }

    private func loadPMPlan() {
        let planURL = repoRoot.appendingPathComponent("sfa-macos/prd.json")

        do {
            let data = try Data(contentsOf: planURL)
            let plan = try JSONDecoder().decode(PMPlanDocument.self, from: data)
            pmStories = plan.userStories.map { story in
                PMStory(
                    id: story.id,
                    title: story.title,
                    wave: story.wave,
                    passed: story.passes,
                    checkpoint: story.checkpointId
                )
            }

            let passed = pmStories.filter(\.passed).count
            appendEvent(
                source: "upm",
                message: "Loaded PM plan from prd.json",
                detail: "\(passed)/\(pmStories.count) stories passed"
            )
        } catch {
            pmStories = Self.fallbackPMStories
            appendEvent(
                source: "upm",
                level: "warning",
                message: "Using fallback PM plan",
                detail: error.localizedDescription
            )
        }
    }

    private func loadLibraryDocument() {
        Task {
            do {
                let document = try await libraryStore.load()
                applyLibraryDocument(document)
                appendEvent(
                    source: "library.store",
                    message: "Loaded local Swift library store",
                    detail: "\(document.tracks.count) tracks | \(document.stems.count) stems | \(document.deckSessions.count) decks | \(document.agentDefinitions.count) agents | \(document.providerRoutes.count) routes | schema v\(document.schemaVersion)"
                )
                pushProgressCard()
            } catch {
                appendEvent(
                    source: "library.store",
                    level: "warning",
                    message: "Could not load local library store",
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func applyLibraryDocument(_ document: SFALibraryDocument) {
        tracks = document.tracks
        processingJobs = document.processingJobs
        cuePoints = document.cuePoints
        deckSessions = document.deckSessions
        performanceSets = document.performanceSets
        dawProjects = document.dawProjects
        dawTracks = document.dawTracks
        dawClips = document.dawClips
        editOperations = document.editOperations
        samplerBanks = document.samplerBanks
        samplerPads = document.samplerPads
        samplePacks = document.samplePacks
        padActions = document.padActions
        crates = document.crates
        crateTrackConfigs = document.crateTrackConfigs
        bigLoopySets = document.bigLoopySets
        controlProfiles = document.controlProfiles
        controlMappings = document.controlMappings
        agentDefinitions = document.agentDefinitions
        agentPromptTemplates = document.agentPromptTemplates
        agentTools = document.agentTools
        agentTasks = document.agentTasks
        agentRuns = document.agentRuns
        llmProviders = document.llmProviders
        modelCapabilities = document.modelCapabilities
        providerRoutes = document.providerRoutes
        localSettings = document.settings
        secureTokenStatus = LocalSecureTokenStore.statusRecords(providerIDs: document.llmProviders.map(\.id))
        agents = Self.agentSummaries(from: document)
        librarySummary = LocalLibrarySummary(document: document)
        pipelineStages = Self.pipelineStages(from: document)
        updateAgentModule(from: document)
        runtime.state = .ready
        runtime.message = "Local Swift store loaded: \(document.tracks.count) tracks, \(document.stems.count) stems, \(document.deckSessions.count) decks, \(document.dawClips.count) clips, \(document.controlMappings.count) mappings, \(document.agentDefinitions.count) agents"
        runtime.checkedAt = document.updatedAt
    }

    private func updateAgentModule(from document: SFALibraryDocument) {
        guard let index = modules.firstIndex(where: { $0.id == "agents" }) else { return }

        modules[index].status = document.agentDefinitions.isEmpty ? .queued : .ready
        modules[index].subtitle = "\(document.agentDefinitions.count) agents, \(document.agentPromptTemplates.count) prompts, \(document.agentTools.count) tools, \(document.providerRoutes.count) provider routes"
        modules[index].owner = "Swift AgentRuntime"
    }

    private static func pipelineStages(from document: SFALibraryDocument) -> [PipelineStage] {
        let jobsByKind = Dictionary(grouping: document.processingJobs, by: \.kind)

        func stage(
            id: String,
            name: String,
            image: String,
            kind: LocalProcessingJob.Kind,
            emptyDetail: String
        ) -> PipelineStage {
            let jobs = jobsByKind[kind] ?? []
            let running = jobs.filter { $0.status == .running }.count
            let queued = jobs.filter { $0.status == .queued }.count
            let ready = jobs.filter { $0.status == .ready }.count
            let failed = jobs.filter { $0.status == .failed }.count
            let total = jobs.count

            let state: PipelineState
            if failed > 0 {
                state = .blocked
            } else if running > 0 {
                state = .running
            } else if queued > 0 {
                state = .queued
            } else if ready > 0 || total > 0 {
                state = .ready
            } else {
                state = .queued
            }

            let detail = total > 0
                ? "\(total) job(s): \(running) running, \(queued) queued, \(ready) ready"
                : emptyDetail
            let progress = total > 0
                ? jobs.map(\.progress).reduce(0, +) / Double(total)
                : 0.05

            return PipelineStage(id: id, name: name, systemImage: image, state: state, detail: detail, progress: progress)
        }

        return [
            PipelineStage(
                id: "import",
                name: "Import",
                systemImage: "tray.and.arrow.down.fill",
                state: document.tracks.isEmpty ? .queued : .ready,
                detail: "\(document.tracks.count) track(s) in local library",
                progress: document.tracks.isEmpty ? 0.05 : 1.0
            ),
            stage(id: "download", name: "Download", image: "arrow.down.circle.fill", kind: .download, emptyDetail: "No native download jobs queued"),
            stage(id: "stems", name: "Stems", image: "waveform.path.ecg", kind: .stems, emptyDetail: "No stem jobs queued"),
            stage(id: "analysis", name: "Analysis", image: "chart.bar.xaxis", kind: .analysis, emptyDetail: "No analysis jobs queued"),
            stage(id: "midi", name: "MIDI", image: "pianokeys", kind: .audioToMIDI, emptyDetail: "No MIDI jobs queued"),
            stage(id: "chords", name: "Chords", image: "music.quarternote.3", kind: .chordDetection, emptyDetail: "No chord jobs queued"),
            stage(id: "warp", name: "Warp", image: "waveform.badge.magnifyingglass", kind: .warp, emptyDetail: "No warp jobs queued"),
            stage(id: "cleanup", name: "Cleanup", image: "sparkle.magnifyingglass", kind: .cleanup, emptyDetail: "No cleanup jobs queued"),
            stage(id: "export", name: "Export", image: "square.and.arrow.up", kind: .export, emptyDetail: "No export jobs queued")
        ]
    }

    private static func agentSummaries(from document: SFALibraryDocument) -> [AgentSummary] {
        document.agentDefinitions.map { agent in
            let latestRun = document.agentRuns
                .filter { $0.agentID == agent.id }
                .sorted { $0.startedAt > $1.startedAt }
                .first
            let latestTask = document.agentTasks
                .filter { $0.agentID == agent.id }
                .sorted { $0.createdAt > $1.createdAt }
                .first

            return AgentSummary(
                id: agent.id,
                name: agent.name,
                role: agent.role,
                status: latestRun?.status.pipelineState ?? latestTask?.status.pipelineState ?? .queued,
                lastOutput: latestRun?.resultSummary ?? agent.description
            )
        }
    }

    private static let seedPipeline = [
        PipelineStage(id: "import", name: "Import", systemImage: "tray.and.arrow.down.fill", state: .ready, detail: "Spotify, local files, sample packs", progress: 1.0),
        PipelineStage(id: "download", name: "Download", systemImage: "arrow.down.circle.fill", state: .queued, detail: "SpotDL primary with fallback", progress: 0.25),
        PipelineStage(id: "stems", name: "Stems", systemImage: "waveform.path.ecg", state: .running, detail: "Demucs or lalal.ai adapter", progress: 0.62),
        PipelineStage(id: "analysis", name: "Analysis", systemImage: "chart.bar.xaxis", state: .queued, detail: "BPM, key, energy, chroma, MFCC", progress: 0.18),
        PipelineStage(id: "midi", name: "MIDI", systemImage: "pianokeys", state: .queued, detail: "Audio-to-MIDI motifs", progress: 0.05),
        PipelineStage(id: "chords", name: "Chords", systemImage: "music.quarternote.3", state: .queued, detail: "Local chord map", progress: 0.05),
        PipelineStage(id: "warp", name: "Warp", systemImage: "waveform.badge.magnifyingglass", state: .queued, detail: "Beat-grid map", progress: 0.05),
        PipelineStage(id: "cleanup", name: "Cleanup", systemImage: "sparkle.magnifyingglass", state: .queued, detail: "Artifact audit", progress: 0.05),
        PipelineStage(id: "export", name: "Export", systemImage: "square.and.arrow.up", state: .queued, detail: "Stems, MIDI, DAW bundle", progress: 0.05)
    ]

    private static let seedModules = [
        FeatureModule(id: "library", title: "Music Library", subtitle: "Tracks, playlists, stems, crates, metadata, and local media references", status: .ready, owner: "Swift LibraryStore", nativeSurface: "Library"),
        FeatureModule(id: "jobs", title: "Processing Pipeline", subtitle: "Local queue execution for download, stems, analysis, MIDI, chords, warp, cleanup, and exports", status: .ready, owner: "Swift ProcessingQueue", nativeSurface: "Pipeline"),
        FeatureModule(id: "dj", title: "DJ Performance", subtitle: "Deck sessions, cue grids, loops, presets, and performance sets", status: .ready, owner: "Swift DeckState", nativeSurface: "DJ"),
        FeatureModule(id: "daw", title: "DAW Workspace", subtitle: "Projects, tracks, clips, edit history, and arrangement export", status: .ready, owner: "Swift ArrangementDocument", nativeSurface: "DAW"),
        FeatureModule(id: "midi", title: "Control Surfaces", subtitle: "MIDI, OSC, profiles, mappings, and actions", status: .ready, owner: "Swift ControlSurfaceRegistry", nativeSurface: "MIDI"),
        FeatureModule(id: "sampler", title: "Sampler And Crates", subtitle: "Sample packs, pad actions, crate digging configs, and Big Loopy sets", status: .ready, owner: "Swift SampleWorkflowStore", nativeSurface: "Samples"),
        FeatureModule(id: "agents", title: "Music Agents", subtitle: "Agent definitions, prompts, tools, provider routes, and local deterministic runs", status: .ready, owner: "Swift AgentRuntime", nativeSurface: "Agents"),
        FeatureModule(id: "showcase", title: "Port Cockpit", subtitle: "PM plan, local telemetry, IPC events, and chat", status: .running, owner: "Swift PortCockpit", nativeSurface: "Port Map")
    ]

    private static let seedAgents = [
        AgentSummary(id: "track-analysis", name: "Track Analysis", role: "Key, BPM, energy", status: .ready, lastOutput: "Ready for harmonic analysis tasks"),
        AgentSummary(id: "mix-planning", name: "Mix Planning", role: "Set sequencing", status: .running, lastOutput: "Waiting on selected crate"),
        AgentSummary(id: "stem-intel", name: "Stem Intelligence", role: "Stem quality", status: .queued, lastOutput: "No active stem batch"),
        AgentSummary(id: "library", name: "Library Agent", role: "Semantic search", status: .ready, lastOutput: "Provider routing available")
    ]

    private static let fallbackPMStories = [
        PMStory(id: "SWIFTPORT-001", title: "Single-bundle runtime and native shell", wave: 1, passed: true, checkpoint: "CP-SWIFT-001"),
        PMStory(id: "SWIFTPORT-002", title: "Port Ecto schemas into Codable local stores", wave: 1, passed: true, checkpoint: "CP-SWIFT-002"),
        PMStory(id: "SWIFTPORT-003", title: "Port audio jobs into local Swift processing queue", wave: 2, passed: true, checkpoint: "CP-SWIFT-003"),
        PMStory(id: "SWIFTPORT-004", title: "Port DJ, DAW, MIDI, sampler, and crate workflows", wave: 3, passed: true, checkpoint: "CP-SWIFT-004"),
        PMStory(id: "SWIFTPORT-005", title: "Port agents and provider routing without server dependency", wave: 4, passed: true, checkpoint: "CP-SWIFT-005"),
        PMStory(id: "SWIFTPORT-006", title: "Ship as a self-contained signed macOS bundle", wave: 5, passed: true, checkpoint: "CP-SWIFT-006")
    ]
}
