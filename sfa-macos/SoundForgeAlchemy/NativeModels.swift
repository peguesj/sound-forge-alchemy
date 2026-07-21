import Foundation

enum NativeSection: String, CaseIterable, Identifiable {
    case library
    case pipeline
    case dj
    case daw
    case midi
    case samples
    case agents
    case showcase
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: return "Library"
        case .pipeline: return "Pipeline"
        case .dj: return "DJ"
        case .daw: return "DAW"
        case .midi: return "MIDI"
        case .samples: return "Samples"
        case .agents: return "Agents"
        case .showcase: return "Showcase"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .pipeline: return "arrow.triangle.branch"
        case .dj: return "headphones"
        case .daw: return "pianokeys"
        case .midi: return "cable.connector"
        case .samples: return "square.grid.3x3.fill"
        case .agents: return "sparkles"
        case .showcase: return "chart.xyaxis.line"
        case .settings: return "gearshape.fill"
        }
    }

    var summary: String {
        switch self {
        case .library: return "Tracks, crates, imports"
        case .pipeline: return "Download, stems, analysis"
        case .dj: return "Decks, cues, performance"
        case .daw: return "Arrangement and export"
        case .midi: return "Controllers and mappings"
        case .samples: return "Packs, pads, alchemy"
        case .agents: return "LLM providers and tasks"
        case .showcase: return "UPM, IPC, SSE, chat"
        case .settings: return "Runtime and adapters"
        }
    }
}

enum PipelineState: String, Codable {
    case queued
    case running
    case ready
    case warning
    case blocked

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .ready: return "Ready"
        case .warning: return "Needs review"
        case .blocked: return "Blocked"
        }
    }
}

struct BundleRuntimeStatus: Equatable {
    enum State: Equatable {
        case indexing
        case ready
        case processing
        case warning
    }

    var state: State = .indexing
    var storageURL: URL = AppConfig.libraryURL
    var message: String = "Loading bundled Swift runtime"
    var checkedAt: Date?

    var isReady: Bool { state == .ready || state == .processing }

    var label: String {
        switch state {
        case .indexing: return "Indexing"
        case .ready: return "Bundled"
        case .processing: return "Processing"
        case .warning: return "Needs review"
        }
    }
}

struct TrackSummary: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var artist: String
    var source: String
    var bpm: Int
    var key: String
    var stage: String
    var progress: Double
}

struct PipelineStage: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var systemImage: String
    var state: PipelineState
    var detail: String
    var progress: Double
}

struct FeatureModule: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var subtitle: String
    var status: PipelineState
    var owner: String
    var nativeSurface: String
}

struct PortedDomain: Identifiable, Hashable, Codable {
    enum Status: String, Hashable, Codable {
        case native
        case porting
        case planned

        var label: String {
            switch self {
            case .native: return "Swift native"
            case .porting: return "Porting"
            case .planned: return "Queued"
            }
        }

        var pipelineState: PipelineState {
            switch self {
            case .native: return .ready
            case .porting: return .running
            case .planned: return .queued
            }
        }
    }

    let id: String
    var name: String
    var sourceModules: [String]
    var swiftTarget: String
    var status: Status
    var notes: String
}

struct PackagingReadinessItem: Identifiable, Hashable {
    let id: String
    var title: String
    var detail: String
    var state: PipelineState
    var systemImage: String
}

struct RuntimeEvent: Identifiable, Hashable {
    let id: String
    var timestamp: Date
    var source: String
    var level: String
    var message: String
    var detail: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        source: String,
        level: String = "info",
        message: String,
        detail: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.level = level
        self.message = message
        self.detail = detail
    }

    var timeLabel: String {
        Self.timeFormatter.string(from: timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct AgentSummary: Identifiable, Hashable {
    let id: String
    var name: String
    var role: String
    var status: PipelineState
    var lastOutput: String
}

struct ShowcaseMessage: Identifiable, Hashable {
    enum Role: String {
        case user
        case assistant
        case system
    }

    let id: String
    var role: Role
    var text: String
    var timestamp: Date
}

struct PMStory: Identifiable, Hashable {
    let id: String
    var title: String
    var wave: Int
    var passed: Bool
    var checkpoint: String
}

struct PMPlanDocument: Decodable {
    let userStories: [PMPlanStory]

    enum CodingKeys: String, CodingKey {
        case userStories = "user_stories"
    }
}

struct PMPlanStory: Decodable {
    let id: String
    let title: String
    let wave: Int
    let checkpointId: String
    let passes: Bool
}
