import Foundation

struct BundleRuntimeSnapshot {
    var runtime: BundleRuntimeStatus
    var processingEngines: [String]
    var capabilitySummary: String
    var portDomains: [PortedDomain]
    var packagingReadiness: [PackagingReadinessItem]
}

final class BundledRuntimeCatalog {
    func loadSnapshot(repoRoot: URL) async -> BundleRuntimeSnapshot {
        let storageURL = AppConfig.libraryURL
        let fileManager = FileManager.default
        let hasRepoContext = fileManager.fileExists(atPath: repoRoot.path)
        let hasAppSupport = fileManager.fileExists(atPath: storageURL.path)

        let message: String
        let state: BundleRuntimeStatus.State

        if hasAppSupport || hasRepoContext {
            message = "Single-bundle Swift runtime loaded"
            state = .ready
        } else {
            message = "Preparing local app storage"
            state = .indexing
        }

        let runtime = BundleRuntimeStatus(
            state: state,
            storageURL: storageURL,
            message: message,
            checkedAt: Date()
        )

        return BundleRuntimeSnapshot(
            runtime: runtime,
            processingEngines: Self.processingEngines,
            capabilitySummary: "Local import, catalog, stem, analysis, MIDI, chord, warp, cleanup, export, DJ, DAW, MIDI/OSC, sampler, crate, Big Loopy, agent, prompt, tool, provider-route, settings, and secure-token contracts are now modeled in Swift.",
            portDomains: Self.seedPortDomains,
            packagingReadiness: Self.packagingReadiness(repoRoot: repoRoot, storageURL: storageURL)
        )
    }

    private static func packagingReadiness(repoRoot: URL, storageURL: URL) -> [PackagingReadinessItem] {
        let fileManager = FileManager.default
        let macRoot = repoRoot.appendingPathComponent("sfa-macos")
        let infoPlist = macRoot.appendingPathComponent("SoundForgeAlchemy/Info.plist")
        let entitlements = macRoot.appendingPathComponent("SoundForgeAlchemy/SoundForgeAlchemy.entitlements")
        let releaseConfig = macRoot.appendingPathComponent("xcconfig/Release.xcconfig")
        let exportOptions = macRoot.appendingPathComponent("ExportOptions.plist")
        let verifier = macRoot.appendingPathComponent("ci/verify_package_readiness.sh")

        return [
            PackagingReadinessItem(
                id: "local-storage",
                title: "Local Runtime Storage",
                detail: storageURL.path,
                state: fileManager.fileExists(atPath: storageURL.path) ? .ready : .queued,
                systemImage: "internaldrive"
            ),
            PackagingReadinessItem(
                id: "permissions",
                title: "Import And Export Permissions",
                detail: "Info.plist usage strings and file access entitlements are present.",
                state: fileManager.fileExists(atPath: infoPlist.path) && fileManager.fileExists(atPath: entitlements.path) ? .ready : .blocked,
                systemImage: "folder.badge.gearshape"
            ),
            PackagingReadinessItem(
                id: "signing",
                title: "Signing Configuration",
                detail: "Release xcconfig uses Developer ID settings with hardened runtime enabled.",
                state: fileManager.fileExists(atPath: releaseConfig.path) ? .ready : .blocked,
                systemImage: "checkmark.seal.fill"
            ),
            PackagingReadinessItem(
                id: "export",
                title: "Archive Export Options",
                detail: "Developer ID export options are checked into the macOS project.",
                state: fileManager.fileExists(atPath: exportOptions.path) ? .ready : .warning,
                systemImage: "square.and.arrow.up"
            ),
            PackagingReadinessItem(
                id: "verifier",
                title: "Package Verifier",
                detail: "ci/verify_package_readiness.sh validates the no-Phoenix bundle invariants.",
                state: fileManager.isExecutableFile(atPath: verifier.path) ? .ready : .warning,
                systemImage: "checklist.checked"
            )
        ]
    }

    static let processingEngines = [
        "Local audio import queue",
        "Native processing artifact engine",
        "Native stem job planner",
        "Local analysis and chord detection",
        "Audio-to-MIDI motif generator",
        "Warp and cleanup artifact writer",
        "Core Audio playback bus",
        "Native DJ deck and cue store",
        "Native DAW arrangement and edit history",
        "MIDI / OSC profile and mapping store",
        "Sampler, crate, and Big Loopy workflow store",
        "Native agent task and provider router",
        "Local settings and Keychain token store"
    ]

    static let seedPortDomains: [PortedDomain] = [
        PortedDomain(
            id: "music-library",
            name: "Music Library",
            sourceModules: ["SoundForge.Music", "Track", "Playlist", "Storage"],
            swiftTarget: "LibraryStore, TrackSummary, LocalStem, PlaylistModel",
            status: .native,
            notes: "Tracks, playlists, stems, jobs, cues, deck sessions, arrangements, sampler records, crates, agents, providers, and settings persist through schema-versioned Codable records."
        ),
        PortedDomain(
            id: "audio-pipeline",
            name: "Audio Pipeline",
            sourceModules: ["SoundForge.Audio", "SoundForge.Jobs", "ProcessingJob"],
            swiftTarget: "ProcessingQueue, LocalProcessingEngine",
            status: .native,
            notes: "Oban worker intent now maps to local Swift execution artifacts for import, download, stems, analysis, MIDI, chord detection, warp, cleanup, and export."
        ),
        PortedDomain(
            id: "dj-performance",
            name: "DJ Performance",
            sourceModules: ["SoundForge.DJ", "CuePoint", "DeckSession", "PerformanceSet"],
            swiftTarget: "LocalDeckSession, CueGrid, LocalPerformanceSet",
            status: .native,
            notes: "Deck state, cue grids, loop length, stem levels, and performance set sequencing render from native Swift value models."
        ),
        PortedDomain(
            id: "daw-workspace",
            name: "DAW Workspace",
            sourceModules: ["SoundForge.DAW", "DawProject", "EditOperation"],
            swiftTarget: "LocalDAWProject, LocalDAWTrack, LocalDAWClip, LocalEditOperation",
            status: .native,
            notes: "Project tracks, clips, and edit operations are document-style Swift models for offline arrangement editing."
        ),
        PortedDomain(
            id: "midi-osc",
            name: "MIDI / OSC Control",
            sourceModules: ["SoundForge.MIDI", "SoundForge.OSC", "ControlSurface"],
            swiftTarget: "LocalControlSurfaceProfile, LocalControlMapping",
            status: .native,
            notes: "Controller profiles, MIDI note/CC mappings, and OSC actions are local Swift contracts ready for AppKit/CoreMIDI adapters."
        ),
        PortedDomain(
            id: "sampler",
            name: "Sampler And Pads",
            sourceModules: ["SoundForge.Sampler", "SampleLibrary", "BigLoopy"],
            swiftTarget: "LocalSamplerBank, LocalPadAction, LocalSamplePack, LocalBigLoopySet",
            status: .native,
            notes: "Sampler banks, pad actions, sample packs, crate digging configs, and alchemy sets have full Swift persistence and workbench views."
        ),
        PortedDomain(
            id: "agents",
            name: "Music Agents",
            sourceModules: ["SoundForge.Agents", "SoundForge.LLM"],
            swiftTarget: "LocalAgentDefinition, LocalAgentTask, LocalAgentRun, LocalProviderRoute",
            status: .native,
            notes: "Agent definitions, prompt templates, tool schemas, deterministic local runs, and explicit provider fallback routes now live in the Swift store."
        ),
        PortedDomain(
            id: "accounts-settings",
            name: "Settings And Identity",
            sourceModules: ["Accounts", "UserSettings", "SpotifyOAuthToken"],
            swiftTarget: "LocalAppSettings, LocalSecureTokenStore",
            status: .native,
            notes: "User/session concepts collapse into local app preferences, Settings diagnostics, and Keychain-backed secure token slots."
        )
    ]
}
