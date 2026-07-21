import Foundation

enum LocalJSONValue: Hashable, Codable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([String: LocalJSONValue])
    case array([LocalJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: LocalJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([LocalJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported local JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct SFALibraryDocument: Codable {
    var schemaVersion: Int = 4
    var tracks: [TrackSummary]
    var playlists: [LocalPlaylist]
    var stems: [LocalStem]
    var processingJobs: [LocalProcessingJob]
    var cuePoints: [LocalCuePoint]
    var deckSessions: [LocalDeckSession]
    var performanceSets: [LocalPerformanceSet]
    var dawProjects: [LocalDAWProject]
    var dawTracks: [LocalDAWTrack]
    var dawClips: [LocalDAWClip]
    var editOperations: [LocalEditOperation]
    var samplerBanks: [LocalSamplerBank]
    var samplerPads: [LocalSamplerPad]
    var samplePacks: [LocalSamplePack]
    var padActions: [LocalPadAction]
    var crates: [LocalCrate]
    var crateTrackConfigs: [LocalCrateTrackConfig]
    var bigLoopySets: [LocalBigLoopySet]
    var controlProfiles: [LocalControlSurfaceProfile]
    var controlMappings: [LocalControlMapping]
    var agentProviders: [LocalAgentProvider]
    var agentDefinitions: [LocalAgentDefinition]
    var agentPromptTemplates: [LocalAgentPromptTemplate]
    var agentTools: [LocalAgentTool]
    var agentTasks: [LocalAgentTask]
    var agentRuns: [LocalAgentRun]
    var llmProviders: [LocalLLMProvider]
    var modelCapabilities: [LocalModelCapability]
    var providerRoutes: [LocalProviderRoute]
    var settings: LocalAppSettings
    var updatedAt: Date

    init(
        schemaVersion: Int = 4,
        tracks: [TrackSummary],
        playlists: [LocalPlaylist],
        stems: [LocalStem] = [],
        processingJobs: [LocalProcessingJob],
        cuePoints: [LocalCuePoint],
        deckSessions: [LocalDeckSession] = [],
        performanceSets: [LocalPerformanceSet] = [],
        dawProjects: [LocalDAWProject],
        dawTracks: [LocalDAWTrack] = [],
        dawClips: [LocalDAWClip] = [],
        editOperations: [LocalEditOperation] = [],
        samplerBanks: [LocalSamplerBank],
        samplerPads: [LocalSamplerPad] = [],
        samplePacks: [LocalSamplePack] = [],
        padActions: [LocalPadAction] = [],
        crates: [LocalCrate],
        crateTrackConfigs: [LocalCrateTrackConfig] = [],
        bigLoopySets: [LocalBigLoopySet] = [],
        controlProfiles: [LocalControlSurfaceProfile],
        controlMappings: [LocalControlMapping] = [],
        agentProviders: [LocalAgentProvider],
        agentDefinitions: [LocalAgentDefinition] = [],
        agentPromptTemplates: [LocalAgentPromptTemplate] = [],
        agentTools: [LocalAgentTool] = [],
        agentTasks: [LocalAgentTask] = [],
        agentRuns: [LocalAgentRun] = [],
        llmProviders: [LocalLLMProvider] = [],
        modelCapabilities: [LocalModelCapability] = [],
        providerRoutes: [LocalProviderRoute] = [],
        settings: LocalAppSettings,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.tracks = tracks
        self.playlists = playlists
        self.stems = stems
        self.processingJobs = processingJobs
        self.cuePoints = cuePoints
        self.deckSessions = deckSessions
        self.performanceSets = performanceSets
        self.dawProjects = dawProjects
        self.dawTracks = dawTracks
        self.dawClips = dawClips
        self.editOperations = editOperations
        self.samplerBanks = samplerBanks
        self.samplerPads = samplerPads
        self.samplePacks = samplePacks
        self.padActions = padActions
        self.crates = crates
        self.crateTrackConfigs = crateTrackConfigs
        self.bigLoopySets = bigLoopySets
        self.controlProfiles = controlProfiles
        self.controlMappings = controlMappings
        self.agentProviders = agentProviders
        self.agentDefinitions = agentDefinitions
        self.agentPromptTemplates = agentPromptTemplates
        self.agentTools = agentTools
        self.agentTasks = agentTasks
        self.agentRuns = agentRuns
        self.llmProviders = llmProviders
        self.modelCapabilities = modelCapabilities
        self.providerRoutes = providerRoutes
        self.settings = settings
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tracks
        case playlists
        case stems
        case processingJobs
        case cuePoints
        case deckSessions
        case performanceSets
        case dawProjects
        case dawTracks
        case dawClips
        case editOperations
        case samplerBanks
        case samplerPads
        case samplePacks
        case padActions
        case crates
        case crateTrackConfigs
        case bigLoopySets
        case controlProfiles
        case controlMappings
        case agentProviders
        case agentDefinitions
        case agentPromptTemplates
        case agentTools
        case agentTasks
        case agentRuns
        case llmProviders
        case modelCapabilities
        case providerRoutes
        case settings
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tracks = try container.decodeIfPresent([TrackSummary].self, forKey: .tracks) ?? []
        playlists = try container.decodeIfPresent([LocalPlaylist].self, forKey: .playlists) ?? []
        stems = try container.decodeIfPresent([LocalStem].self, forKey: .stems) ?? []
        processingJobs = try container.decodeIfPresent([LocalProcessingJob].self, forKey: .processingJobs) ?? []
        cuePoints = try container.decodeIfPresent([LocalCuePoint].self, forKey: .cuePoints) ?? []
        deckSessions = try container.decodeIfPresent([LocalDeckSession].self, forKey: .deckSessions) ?? []
        performanceSets = try container.decodeIfPresent([LocalPerformanceSet].self, forKey: .performanceSets) ?? []
        dawProjects = try container.decodeIfPresent([LocalDAWProject].self, forKey: .dawProjects) ?? []
        dawTracks = try container.decodeIfPresent([LocalDAWTrack].self, forKey: .dawTracks) ?? []
        dawClips = try container.decodeIfPresent([LocalDAWClip].self, forKey: .dawClips) ?? []
        editOperations = try container.decodeIfPresent([LocalEditOperation].self, forKey: .editOperations) ?? []
        samplerBanks = try container.decodeIfPresent([LocalSamplerBank].self, forKey: .samplerBanks) ?? []
        samplerPads = try container.decodeIfPresent([LocalSamplerPad].self, forKey: .samplerPads) ?? []
        samplePacks = try container.decodeIfPresent([LocalSamplePack].self, forKey: .samplePacks) ?? []
        padActions = try container.decodeIfPresent([LocalPadAction].self, forKey: .padActions) ?? []
        crates = try container.decodeIfPresent([LocalCrate].self, forKey: .crates) ?? []
        crateTrackConfigs = try container.decodeIfPresent([LocalCrateTrackConfig].self, forKey: .crateTrackConfigs) ?? []
        bigLoopySets = try container.decodeIfPresent([LocalBigLoopySet].self, forKey: .bigLoopySets) ?? []
        controlProfiles = try container.decodeIfPresent([LocalControlSurfaceProfile].self, forKey: .controlProfiles) ?? []
        controlMappings = try container.decodeIfPresent([LocalControlMapping].self, forKey: .controlMappings) ?? []
        agentProviders = try container.decodeIfPresent([LocalAgentProvider].self, forKey: .agentProviders) ?? []
        agentDefinitions = try container.decodeIfPresent([LocalAgentDefinition].self, forKey: .agentDefinitions) ?? []
        agentPromptTemplates = try container.decodeIfPresent([LocalAgentPromptTemplate].self, forKey: .agentPromptTemplates) ?? []
        agentTools = try container.decodeIfPresent([LocalAgentTool].self, forKey: .agentTools) ?? []
        agentTasks = try container.decodeIfPresent([LocalAgentTask].self, forKey: .agentTasks) ?? []
        agentRuns = try container.decodeIfPresent([LocalAgentRun].self, forKey: .agentRuns) ?? []
        llmProviders = try container.decodeIfPresent([LocalLLMProvider].self, forKey: .llmProviders) ?? []
        modelCapabilities = try container.decodeIfPresent([LocalModelCapability].self, forKey: .modelCapabilities) ?? []
        providerRoutes = try container.decodeIfPresent([LocalProviderRoute].self, forKey: .providerRoutes) ?? []
        settings = try container.decodeIfPresent(LocalAppSettings.self, forKey: .settings) ?? LocalAppSettings()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        if schemaVersion < 4 {
            schemaVersion = 4
        }
    }

    static let seed = SFALibraryDocument(
        tracks: [
            TrackSummary(id: "seed-1", title: "Midnight Copper", artist: "Local crate", source: "Library", bpm: 124, key: "8A", stage: "Analysis ready", progress: 1.0),
            TrackSummary(id: "seed-2", title: "Granular Sunrise", artist: "Imported track", source: "Library", bpm: 118, key: "5B", stage: "Stem preview", progress: 0.72),
            TrackSummary(id: "seed-3", title: "Warehouse Bloom", artist: "Sample pack", source: "Samples", bpm: 132, key: "11A", stage: "Download queued", progress: 0.18)
        ],
        playlists: [
            LocalPlaylist(id: "playlist-working-set", name: "Working Set", trackIDs: ["seed-1", "seed-2"], source: "local")
        ],
        stems: [
            LocalStem(id: "stem-seed-2-vocals", trackID: "seed-2", processingJobID: "job-seed-stems", type: .vocals, filePath: nil, fileSize: nil, source: "planned", options: ["engine": .string("local-stem-planner")]),
            LocalStem(id: "stem-seed-2-drums", trackID: "seed-2", processingJobID: "job-seed-stems", type: .drums, filePath: nil, fileSize: nil, source: "planned", options: ["engine": .string("local-stem-planner")]),
            LocalStem(id: "stem-seed-2-bass", trackID: "seed-2", processingJobID: "job-seed-stems", type: .bass, filePath: nil, fileSize: nil, source: "planned", options: ["engine": .string("local-stem-planner")]),
            LocalStem(id: "stem-seed-2-other", trackID: "seed-2", processingJobID: "job-seed-stems", type: .other, filePath: nil, fileSize: nil, source: "planned", options: ["engine": .string("local-stem-planner")])
        ],
        processingJobs: [
            LocalProcessingJob(id: "job-seed-stems", trackID: "seed-2", kind: .stems, status: .running, progress: 0.62, detail: "Stem planning queued in local runtime"),
            LocalProcessingJob(id: "job-seed-analysis", trackID: "seed-1", kind: .analysis, status: .ready, progress: 1.0, detail: "Analysis metadata available")
        ],
        cuePoints: [
            LocalCuePoint(id: "cue-seed-1-drop", trackID: "seed-1", label: "Drop", seconds: 64.0, colorHex: "#349ECB")
        ],
        deckSessions: [
            LocalDeckSession(
                id: "deck-seed-a",
                name: "Deck A",
                deck: "A",
                trackID: "seed-1",
                bpm: 124.0,
                key: "8A",
                isPlaying: true,
                pitch: 0.0,
                loopLengthBeats: 8,
                cuePointIDs: ["cue-seed-1-drop"],
                stemLevels: ["vocals": 0.86, "drums": 0.92, "bass": 0.78, "other": 0.58]
            ),
            LocalDeckSession(
                id: "deck-seed-b",
                name: "Deck B",
                deck: "B",
                trackID: "seed-2",
                bpm: 118.0,
                key: "5B",
                isPlaying: false,
                pitch: 2.5,
                loopLengthBeats: 16,
                cuePointIDs: [],
                stemLevels: ["vocals": 0.64, "drums": 0.88, "bass": 0.72, "other": 0.44]
            )
        ],
        performanceSets: [
            LocalPerformanceSet(
                id: "perf-seed-chef",
                name: "Copper Sunrise Chef Set",
                mode: "chef_set",
                deckSessionIDs: ["deck-seed-a", "deck-seed-b"],
                cuePointIDs: ["cue-seed-1-drop"],
                notes: "Native set plan for cue grids, loops, and cross-deck performance recipes."
            )
        ],
        dawProjects: [
            LocalDAWProject(id: "daw-seed-session", name: "Alchemy Session", trackIDs: ["seed-1", "seed-2"], tempo: 124, key: "8A")
        ],
        dawTracks: [
            LocalDAWTrack(
                id: "daw-track-vocals",
                projectID: "daw-seed-session",
                title: "Vocals",
                position: 0,
                trackType: "audio",
                audioTrackID: "seed-2",
                metadata: ["color": .string("#8B5CF6"), "solo": .bool(false), "mute": .bool(false)]
            ),
            LocalDAWTrack(
                id: "daw-track-drums",
                projectID: "daw-seed-session",
                title: "Drums",
                position: 1,
                trackType: "stem",
                audioTrackID: "seed-2",
                metadata: ["color": .string("#D97706"), "solo": .bool(false), "mute": .bool(false)]
            )
        ],
        dawClips: [
            LocalDAWClip(id: "clip-vocal-hook", projectID: "daw-seed-session", trackID: "daw-track-vocals", sourceTrackID: "seed-2", stemID: "stem-seed-2-vocals", startBeat: 16, lengthBeats: 24, gain: -1.5, muted: false),
            LocalDAWClip(id: "clip-drum-loop", projectID: "daw-seed-session", trackID: "daw-track-drums", sourceTrackID: "seed-2", stemID: "stem-seed-2-drums", startBeat: 0, lengthBeats: 32, gain: 0.0, muted: false)
        ],
        editOperations: [
            LocalEditOperation(id: "edit-fade-vocal", stemID: "stem-seed-2-vocals", operationType: "fade_in", params: ["duration_beats": .integer(4)], position: 16),
            LocalEditOperation(id: "edit-gain-drums", stemID: "stem-seed-2-drums", operationType: "gain", params: ["db": .number(1.8)], position: 0)
        ],
        samplerBanks: [
            LocalSamplerBank(id: "bank-seed-drums", name: "Starter Pads", padCount: 16)
        ],
        samplerPads: [
            LocalSamplerPad(id: "pad-seed-0", bankID: "bank-seed-drums", index: 0, label: "Kick", colorHex: "#6B7280", stemID: nil, volume: 0.95, pitch: 0, velocity: 1, startTime: 0, endTime: nil, synthConfig: [:]),
            LocalSamplerPad(id: "pad-seed-1", bankID: "bank-seed-drums", index: 1, label: "Vocal", colorHex: "#349ECB", stemID: "stem-seed-2-vocals", volume: 0.82, pitch: 0, velocity: 0.9, startTime: 0, endTime: nil, synthConfig: [:])
        ],
        samplePacks: [
            LocalSamplePack(id: "pack-seed-drums", name: "Starter Drums", source: "local", category: "drums", bpmMin: 118, bpmMax: 132, key: "Any", totalFiles: 16, status: "ready", manifestPath: nil)
        ],
        padActions: [
            LocalPadAction(id: "pad-action-kick", padID: "pad-seed-0", trigger: "note_on:36", action: "trigger_sample", params: ["velocity_sensitive": .bool(true)]),
            LocalPadAction(id: "pad-action-vocal", padID: "pad-seed-1", trigger: "note_on:37", action: "trigger_stem", params: ["stem_type": .string("vocals")])
        ],
        crates: [
            LocalCrate(id: "crate-seed-local", name: "Local Crate", trackIDs: ["seed-1", "seed-3"], notes: "Seeded from the Swift local store")
        ],
        crateTrackConfigs: [
            LocalCrateTrackConfig(
                id: "crate-config-seed-1",
                crateID: "crate-seed-local",
                trackID: "seed-1",
                stemOverride: [
                    "enabled": .bool(true),
                    "preferred_stems": .array([.string("drums"), .string("bass")]),
                    "energy_floor": .number(0.72)
                ]
            )
        ],
        bigLoopySets: [
            LocalBigLoopySet(
                id: "loopy-seed-performance",
                name: "Warehouse Bloom Loops",
                type: "performance_set",
                sourceTrackIDs: ["seed-1", "seed-2"],
                recipe: [
                    "bars": .integer(8),
                    "slices": .integer(16),
                    "mode": .string("omega_chop")
                ],
                outputFormat: "ableton_bundle",
                status: "complete",
                performanceSet: ["source": .string("perf-seed-chef"), "roundtrip_ready": .bool(true)]
            )
        ],
        controlProfiles: [
            LocalControlSurfaceProfile(id: "profile-touchosc", name: "TouchOSC Bridge", transport: .osc, mappings: 24),
            LocalControlSurfaceProfile(id: "profile-mpc-live", name: "Akai MPC Live II", transport: .midi, mappings: 16)
        ],
        controlMappings: [
            LocalControlMapping(id: "mapping-mpc-pad-36", profileID: "profile-mpc-live", deviceName: "Akai MPC Live II", midiType: "note_on", channel: 1, number: 36, action: "stem_solo", params: ["stem": .string("drums")]),
            LocalControlMapping(id: "mapping-mpc-q-link", profileID: "profile-mpc-live", deviceName: "Akai MPC Live II", midiType: "cc", channel: 1, number: 16, action: "stem_volume", params: ["stem": .string("vocals")]),
            LocalControlMapping(id: "mapping-touchosc-play", profileID: "profile-touchosc", deviceName: "TouchOSC Bridge", midiType: "cc", channel: 1, number: 118, action: "play", params: ["deck": .string("A")])
        ],
        agentProviders: [
            LocalAgentProvider(id: "provider-local", name: "Local Provider Router", kind: .local, enabled: true)
        ],
        agentDefinitions: [
            LocalAgentDefinition(
                id: "agent-sonic-analyst",
                name: "Sonic Analyst",
                role: "BPM, key, energy, and mix compatibility",
                description: "Profiles audio features and scores transition compatibility between selected tracks.",
                capabilities: ["audio_analysis", "bpm_detection", "key_analysis", "energy_profiling", "mix_compatibility"],
                preferredTask: "analysis",
                preferredSpeed: "fast",
                systemPromptID: "prompt-sonic-analyst",
                defaultToolIDs: ["tool-get-track-context", "tool-score-harmonic-match"]
            ),
            LocalAgentDefinition(
                id: "agent-crate-analyst",
                name: "Crate Analyst",
                role: "Crate DNA and set-use recommendations",
                description: "Summarizes crate genre boundaries, era range, mood arc, and use cases.",
                capabilities: ["crate_analysis", "genre_detection", "mood_profiling"],
                preferredTask: "analysis",
                preferredSpeed: "balanced",
                systemPromptID: "prompt-crate-analyst",
                defaultToolIDs: ["tool-get-crate-context"]
            ),
            LocalAgentDefinition(
                id: "agent-mix-planner",
                name: "Mix Planner",
                role: "Set sequencing and transition notes",
                description: "Builds a performance plan from tracks, cue grids, decks, and crate context.",
                capabilities: ["set_planning", "transition_design", "cue_strategy"],
                preferredTask: "tool_use",
                preferredSpeed: "balanced",
                systemPromptID: "prompt-mix-planner",
                defaultToolIDs: ["tool-get-track-context", "tool-get-crate-context"]
            )
        ],
        agentPromptTemplates: [
            LocalAgentPromptTemplate(
                id: "prompt-sonic-analyst",
                agentID: "agent-sonic-analyst",
                name: "Sonic compatibility JSON",
                system: "You are a professional DJ and audio analyst. Return structured JSON with compatibility_score, tempo_match, key_compatible, energy_delta, mix_notes, and tracks.",
                userTemplate: "Analyze {{track_ids}} for BPM, key, energy, and mix compatibility.",
                outputSchema: [
                    "type": .string("object"),
                    "required": .array([.string("compatibility_score"), .string("mix_notes"), .string("tracks")])
                ]
            ),
            LocalAgentPromptTemplate(
                id: "prompt-crate-analyst",
                agentID: "agent-crate-analyst",
                name: "Crate DNA JSON",
                system: "You are a music curator. Return JSON with genre_tags, era_range, mood_arc, dna_summary, and suggested_use_cases.",
                userTemplate: "Summarize crate {{crate_id}} using track and audio feature context.",
                outputSchema: [
                    "type": .string("object"),
                    "required": .array([.string("genre_tags"), .string("dna_summary"), .string("suggested_use_cases")])
                ]
            ),
            LocalAgentPromptTemplate(
                id: "prompt-mix-planner",
                agentID: "agent-mix-planner",
                name: "Performance plan JSON",
                system: "You are a DJ performance planner. Return JSON with ordered_tracks, transition_notes, cue_strategy, and risk_flags.",
                userTemplate: "Create a playable set plan from {{track_ids}} and crate {{crate_id}}.",
                outputSchema: [
                    "type": .string("object"),
                    "required": .array([.string("ordered_tracks"), .string("transition_notes")])
                ]
            )
        ],
        agentTools: [
            LocalAgentTool(
                id: "tool-get-track-context",
                name: "get_track_context",
                description: "Retrieves local track metadata, stem state, cue points, and processing state for given track IDs.",
                paramsSchema: [
                    "type": .string("object"),
                    "properties": .object(["track_ids": .object(["type": .string("array")])]),
                    "required": .array([.string("track_ids")])
                ],
                target: "local_library",
                enabled: true
            ),
            LocalAgentTool(
                id: "tool-get-crate-context",
                name: "get_crate_context",
                description: "Reads local crate membership and crate digging overrides.",
                paramsSchema: [
                    "type": .string("object"),
                    "properties": .object(["crate_id": .object(["type": .string("string")])]),
                    "required": .array([.string("crate_id")])
                ],
                target: "local_crate_store",
                enabled: true
            ),
            LocalAgentTool(
                id: "tool-score-harmonic-match",
                name: "score_harmonic_match",
                description: "Scores Camelot-key compatibility and tempo drift for selected tracks.",
                paramsSchema: [
                    "type": .string("object"),
                    "properties": .object(["track_ids": .object(["type": .string("array")])]),
                    "required": .array([.string("track_ids")])
                ],
                target: "local_analysis_store",
                enabled: true
            )
        ],
        agentTasks: [
            LocalAgentTask(
                id: "agent-task-seed-crate",
                agentID: "agent-crate-analyst",
                instruction: "Generate a crate DNA card for the local working crate.",
                status: .ready,
                trackIDs: ["seed-1", "seed-3"],
                crateID: "crate-seed-local",
                toolIDs: ["tool-get-crate-context"],
                routeID: "route-crate-analyst",
                createdAt: Date()
            )
        ],
        agentRuns: [
            LocalAgentRun(
                id: "agent-run-seed-crate",
                taskID: "agent-task-seed-crate",
                agentID: "agent-crate-analyst",
                providerID: "llm-local-planner",
                model: "local-offline-planner",
                status: .ready,
                resultSummary: "Local crate has a 124-132 BPM performance window with sample-pack material ready for set planning.",
                usage: ["input_tokens": 142, "output_tokens": 61],
                output: [
                    "genre_tags": .array([.string("local crate"), .string("sample-forward")]),
                    "mood_arc": .string("Focused warm-up material that can build into a brighter warehouse peak."),
                    "suggested_use_cases": .array([.string("warm-up set"), .string("sample prep")])
                ],
                startedAt: Date(),
                completedAt: Date()
            )
        ],
        llmProviders: [
            LocalLLMProvider(
                id: "llm-local-planner",
                name: "Local Offline Planner",
                providerType: "local",
                baseURL: nil,
                defaultModel: "local-offline-planner",
                enabled: true,
                priority: 0,
                healthStatus: "healthy",
                isSystem: false,
                capabilities: ["chat", "json_mode", "tool_use"]
            ),
            LocalLLMProvider(
                id: "llm-ollama-system",
                name: "Ollama System",
                providerType: "ollama",
                baseURL: "http://localhost:11434",
                defaultModel: "llama3.2",
                enabled: false,
                priority: 1000,
                healthStatus: "unknown",
                isSystem: true,
                capabilities: ["chat", "tool_use"]
            ),
            LocalLLMProvider(
                id: "llm-openai-user",
                name: "OpenAI User Slot",
                providerType: "openai",
                baseURL: "https://api.openai.com/v1",
                defaultModel: "gpt-4o",
                enabled: false,
                priority: 1001,
                healthStatus: "unknown",
                isSystem: false,
                capabilities: ["chat", "vision", "tool_use", "json_mode", "audio"]
            )
        ],
        modelCapabilities: [
            LocalModelCapability(id: "model-local-offline-planner", providerType: "local", model: "local-offline-planner", speed: "fast", quality: "medium", cost: "free", contextWindow: 32000, features: ["chat", "json_mode", "tool_use"]),
            LocalModelCapability(id: "model-ollama-llama32", providerType: "ollama", model: "llama3.2", speed: "medium", quality: "medium", cost: "free", contextWindow: 128000, features: ["chat", "tool_use"]),
            LocalModelCapability(id: "model-openai-gpt4o", providerType: "openai", model: "gpt-4o", speed: "medium", quality: "high", cost: "medium", contextWindow: 128000, features: ["chat", "vision", "tool_use", "json_mode", "audio"])
        ],
        providerRoutes: [
            LocalProviderRoute(
                id: "route-sonic-analyst",
                agentID: "agent-sonic-analyst",
                taskType: "analysis",
                preferredProviderIDs: ["llm-local-planner"],
                fallbackProviderIDs: ["llm-ollama-system", "llm-openai-user"],
                prefer: "speed",
                requiredFeatures: ["chat", "json_mode"],
                maxTokens: 512,
                temperature: 0.3
            ),
            LocalProviderRoute(
                id: "route-crate-analyst",
                agentID: "agent-crate-analyst",
                taskType: "analysis",
                preferredProviderIDs: ["llm-local-planner"],
                fallbackProviderIDs: ["llm-ollama-system"],
                prefer: "quality",
                requiredFeatures: ["chat", "json_mode"],
                maxTokens: 600,
                temperature: 0.4
            ),
            LocalProviderRoute(
                id: "route-mix-planner",
                agentID: "agent-mix-planner",
                taskType: "tool_use",
                preferredProviderIDs: ["llm-local-planner"],
                fallbackProviderIDs: ["llm-ollama-system", "llm-openai-user"],
                prefer: "quality",
                requiredFeatures: ["chat", "tool_use"],
                maxTokens: 900,
                temperature: 0.5
            )
        ],
        settings: LocalAppSettings(),
        updatedAt: Date()
    )
}

struct LocalLibrarySummary: Equatable {
    var schemaVersion: Int
    var totalRecords: Int
    var updatedAt: Date?
    var domains: [LocalStoreDomainSummary]

    static let empty = LocalLibrarySummary(schemaVersion: 4, totalRecords: 0, updatedAt: nil, domains: [])

    init(document: SFALibraryDocument) {
        let domains = [
            LocalStoreDomainSummary(id: "tracks", label: "Tracks", count: document.tracks.count, systemImage: "music.note.list"),
            LocalStoreDomainSummary(id: "playlists", label: "Playlists", count: document.playlists.count, systemImage: "rectangle.stack.fill"),
            LocalStoreDomainSummary(id: "stems", label: "Stems", count: document.stems.count, systemImage: "waveform.path.ecg"),
            LocalStoreDomainSummary(id: "jobs", label: "Jobs", count: document.processingJobs.count, systemImage: "arrow.triangle.branch"),
            LocalStoreDomainSummary(id: "cues", label: "Cue points", count: document.cuePoints.count, systemImage: "flag.fill"),
            LocalStoreDomainSummary(id: "decks", label: "Deck sessions", count: document.deckSessions.count, systemImage: "headphones"),
            LocalStoreDomainSummary(id: "performance", label: "Performance sets", count: document.performanceSets.count, systemImage: "rectangle.3.group.fill"),
            LocalStoreDomainSummary(id: "daw", label: "DAW projects", count: document.dawProjects.count, systemImage: "pianokeys"),
            LocalStoreDomainSummary(id: "daw-tracks", label: "DAW tracks", count: document.dawTracks.count, systemImage: "timeline.selection"),
            LocalStoreDomainSummary(id: "clips", label: "DAW clips", count: document.dawClips.count, systemImage: "waveform"),
            LocalStoreDomainSummary(id: "edits", label: "Edit operations", count: document.editOperations.count, systemImage: "scissors"),
            LocalStoreDomainSummary(id: "sampler", label: "Sampler pads", count: document.samplerPads.count, systemImage: "square.grid.3x3.fill"),
            LocalStoreDomainSummary(id: "packs", label: "Sample packs", count: document.samplePacks.count, systemImage: "shippingbox"),
            LocalStoreDomainSummary(id: "pad-actions", label: "Pad actions", count: document.padActions.count, systemImage: "square.grid.3x3.topleft.filled"),
            LocalStoreDomainSummary(id: "crates", label: "Crates", count: document.crates.count, systemImage: "shippingbox.fill"),
            LocalStoreDomainSummary(id: "crate-configs", label: "Crate configs", count: document.crateTrackConfigs.count, systemImage: "music.note.house.fill"),
            LocalStoreDomainSummary(id: "loopy", label: "Big Loopy sets", count: document.bigLoopySets.count, systemImage: "loop"),
            LocalStoreDomainSummary(id: "controls", label: "Control profiles", count: document.controlProfiles.count, systemImage: "slider.horizontal.3"),
            LocalStoreDomainSummary(id: "mappings", label: "Control mappings", count: document.controlMappings.count, systemImage: "cable.connector"),
            LocalStoreDomainSummary(id: "providers", label: "Providers", count: document.agentProviders.count, systemImage: "sparkles"),
            LocalStoreDomainSummary(id: "agents", label: "Agent definitions", count: document.agentDefinitions.count, systemImage: "person.2.wave.2.fill"),
            LocalStoreDomainSummary(id: "agent-prompts", label: "Agent prompts", count: document.agentPromptTemplates.count, systemImage: "text.badge.star"),
            LocalStoreDomainSummary(id: "agent-tools", label: "Agent tools", count: document.agentTools.count, systemImage: "wrench.and.screwdriver.fill"),
            LocalStoreDomainSummary(id: "agent-tasks", label: "Agent tasks", count: document.agentTasks.count, systemImage: "checklist"),
            LocalStoreDomainSummary(id: "agent-runs", label: "Agent runs", count: document.agentRuns.count, systemImage: "play.square.stack.fill"),
            LocalStoreDomainSummary(id: "llm-providers", label: "LLM providers", count: document.llmProviders.count, systemImage: "network"),
            LocalStoreDomainSummary(id: "models", label: "Model capabilities", count: document.modelCapabilities.count, systemImage: "cpu"),
            LocalStoreDomainSummary(id: "routes", label: "Provider routes", count: document.providerRoutes.count, systemImage: "point.topleft.down.curvedto.point.bottomright.up"),
            LocalStoreDomainSummary(id: "settings", label: "Settings", count: 1, systemImage: "gearshape.fill")
        ]

        self.schemaVersion = document.schemaVersion
        self.totalRecords = domains.map(\.count).reduce(0, +)
        self.updatedAt = document.updatedAt
        self.domains = domains
    }

    private init(schemaVersion: Int, totalRecords: Int, updatedAt: Date?, domains: [LocalStoreDomainSummary]) {
        self.schemaVersion = schemaVersion
        self.totalRecords = totalRecords
        self.updatedAt = updatedAt
        self.domains = domains
    }
}

struct LocalStoreDomainSummary: Identifiable, Hashable {
    let id: String
    var label: String
    var count: Int
    var systemImage: String
}

struct LocalPlaylist: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var trackIDs: [String]
    var source: String
}

struct LocalStem: Identifiable, Hashable, Codable {
    enum StemType: String, CaseIterable, Codable {
        case vocals
        case drums
        case bass
        case other
        case guitar
        case piano
        case electricGuitar = "electric_guitar"
        case acousticGuitar = "acoustic_guitar"
        case synth
        case strings
        case wind

        static let defaultSeparationSet: [StemType] = [.vocals, .drums, .bass, .other]

        var label: String {
            switch self {
            case .vocals: return "Vocals"
            case .drums: return "Drums"
            case .bass: return "Bass"
            case .other: return "Other"
            case .guitar: return "Guitar"
            case .piano: return "Piano"
            case .electricGuitar: return "Electric guitar"
            case .acousticGuitar: return "Acoustic guitar"
            case .synth: return "Synth"
            case .strings: return "Strings"
            case .wind: return "Wind"
            }
        }
    }

    let id: String
    var trackID: String
    var processingJobID: String?
    var type: StemType
    var filePath: String?
    var fileSize: Int?
    var source: String
    var options: [String: LocalJSONValue]
}

struct LocalProcessingJob: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case importAudio
        case download
        case stems
        case analysis
        case audioToMIDI
        case chordDetection
        case warp
        case cleanup
        case export

        var label: String {
            switch self {
            case .importAudio: return "Import"
            case .download: return "Download"
            case .stems: return "Stem plan"
            case .analysis: return "Analysis"
            case .audioToMIDI: return "Audio to MIDI"
            case .chordDetection: return "Chord detection"
            case .warp: return "Warp"
            case .cleanup: return "Cleanup"
            case .export: return "Export"
            }
        }

        var systemImage: String {
            switch self {
            case .importAudio: return "tray.and.arrow.down.fill"
            case .download: return "arrow.down.circle.fill"
            case .stems: return "waveform.path.ecg"
            case .analysis: return "chart.bar.xaxis"
            case .audioToMIDI: return "pianokeys"
            case .chordDetection: return "music.quarternote.3"
            case .warp: return "waveform.badge.magnifyingglass"
            case .cleanup: return "sparkle.magnifyingglass"
            case .export: return "square.and.arrow.up"
            }
        }
    }

    enum Status: String, Codable {
        case queued
        case running
        case ready
        case failed

        var pipelineState: PipelineState {
            switch self {
            case .queued: return .queued
            case .running: return .running
            case .ready: return .ready
            case .failed: return .blocked
            }
        }

        var label: String {
            switch self {
            case .queued: return "Queued"
            case .running: return "Running"
            case .ready: return "Ready"
            case .failed: return "Failed"
            }
        }
    }

    let id: String
    var trackID: String
    var kind: Kind
    var status: Status
    var progress: Double
    var detail: String
    var outputPath: String?
    var artifactPaths: [String]?
    var completedAt: Date?
    var createdAt: Date = Date()
}

struct LocalCuePoint: Identifiable, Hashable, Codable {
    let id: String
    var trackID: String
    var label: String
    var seconds: Double
    var colorHex: String
}

struct LocalDeckSession: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var deck: String
    var trackID: String
    var bpm: Double
    var key: String
    var isPlaying: Bool
    var pitch: Double
    var loopLengthBeats: Int
    var cuePointIDs: [String]
    var stemLevels: [String: Double]
}

struct LocalPerformanceSet: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var mode: String
    var deckSessionIDs: [String]
    var cuePointIDs: [String]
    var notes: String
}

struct LocalDAWProject: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var trackIDs: [String]
    var tempo: Int
    var key: String
}

struct LocalDAWTrack: Identifiable, Hashable, Codable {
    let id: String
    var projectID: String
    var title: String
    var position: Int
    var trackType: String
    var audioTrackID: String?
    var metadata: [String: LocalJSONValue]
}

struct LocalDAWClip: Identifiable, Hashable, Codable {
    let id: String
    var projectID: String
    var trackID: String
    var sourceTrackID: String?
    var stemID: String?
    var startBeat: Double
    var lengthBeats: Double
    var gain: Double
    var muted: Bool
}

struct LocalEditOperation: Identifiable, Hashable, Codable {
    let id: String
    var stemID: String?
    var operationType: String
    var params: [String: LocalJSONValue]
    var position: Double
}

struct LocalSamplerBank: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var padCount: Int
}

struct LocalSamplerPad: Identifiable, Hashable, Codable {
    let id: String
    var bankID: String
    var index: Int
    var label: String
    var colorHex: String
    var stemID: String?
    var volume: Double
    var pitch: Double
    var velocity: Double
    var startTime: Double
    var endTime: Double?
    var synthConfig: [String: LocalJSONValue]
}

struct LocalSamplePack: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var source: String
    var category: String
    var bpmMin: Int
    var bpmMax: Int
    var key: String
    var totalFiles: Int
    var status: String
    var manifestPath: String?
}

struct LocalPadAction: Identifiable, Hashable, Codable {
    let id: String
    var padID: String
    var trigger: String
    var action: String
    var params: [String: LocalJSONValue]
}

struct LocalCrate: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var trackIDs: [String]
    var notes: String
}

struct LocalCrateTrackConfig: Identifiable, Hashable, Codable {
    let id: String
    var crateID: String
    var trackID: String
    var stemOverride: [String: LocalJSONValue]
}

struct LocalBigLoopySet: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var type: String
    var sourceTrackIDs: [String]
    var recipe: [String: LocalJSONValue]
    var outputFormat: String
    var status: String
    var performanceSet: [String: LocalJSONValue]
}

struct LocalControlSurfaceProfile: Identifiable, Hashable, Codable {
    enum Transport: String, Codable {
        case midi
        case osc
        case bluetooth
    }

    let id: String
    var name: String
    var transport: Transport
    var mappings: Int
}

struct LocalControlMapping: Identifiable, Hashable, Codable {
    let id: String
    var profileID: String
    var deviceName: String
    var midiType: String
    var channel: Int
    var number: Int
    var action: String
    var params: [String: LocalJSONValue]
}

struct LocalAgentProvider: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case local
        case openAICompatible
        case ollama
        case lmStudio
    }

    let id: String
    var name: String
    var kind: Kind
    var enabled: Bool
    var baseURL: String?
    var defaultModel: String?
    var priority: Int?
}

struct LocalAgentDefinition: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var role: String
    var description: String
    var capabilities: [String]
    var preferredTask: String
    var preferredSpeed: String
    var systemPromptID: String
    var defaultToolIDs: [String]
}

struct LocalAgentPromptTemplate: Identifiable, Hashable, Codable {
    let id: String
    var agentID: String
    var name: String
    var system: String
    var userTemplate: String
    var outputSchema: [String: LocalJSONValue]
}

struct LocalAgentTool: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var description: String
    var paramsSchema: [String: LocalJSONValue]
    var target: String
    var enabled: Bool
}

struct LocalAgentTask: Identifiable, Hashable, Codable {
    enum Status: String, Codable {
        case queued
        case running
        case ready
        case failed

        var pipelineState: PipelineState {
            switch self {
            case .queued: return .queued
            case .running: return .running
            case .ready: return .ready
            case .failed: return .blocked
            }
        }

        var label: String {
            switch self {
            case .queued: return "Queued"
            case .running: return "Running"
            case .ready: return "Ready"
            case .failed: return "Failed"
            }
        }
    }

    let id: String
    var agentID: String
    var instruction: String
    var status: Status
    var trackIDs: [String]
    var crateID: String?
    var toolIDs: [String]
    var routeID: String?
    var createdAt: Date
}

struct LocalAgentRun: Identifiable, Hashable, Codable {
    enum Status: String, Codable {
        case queued
        case running
        case ready
        case failed

        var pipelineState: PipelineState {
            switch self {
            case .queued: return .queued
            case .running: return .running
            case .ready: return .ready
            case .failed: return .blocked
            }
        }

        var label: String {
            switch self {
            case .queued: return "Queued"
            case .running: return "Running"
            case .ready: return "Ready"
            case .failed: return "Failed"
            }
        }
    }

    let id: String
    var taskID: String
    var agentID: String
    var providerID: String?
    var model: String?
    var status: Status
    var resultSummary: String
    var usage: [String: Int]
    var output: [String: LocalJSONValue]
    var startedAt: Date
    var completedAt: Date?
}

struct LocalLLMProvider: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var providerType: String
    var baseURL: String?
    var defaultModel: String?
    var enabled: Bool
    var priority: Int
    var healthStatus: String
    var isSystem: Bool
    var capabilities: [String]

    var pipelineState: PipelineState {
        if !enabled {
            return .queued
        }
        return healthStatus == "healthy" ? .ready : .warning
    }
}

struct LocalModelCapability: Identifiable, Hashable, Codable {
    let id: String
    var providerType: String
    var model: String
    var speed: String
    var quality: String
    var cost: String
    var contextWindow: Int
    var features: [String]
}

struct LocalProviderRoute: Identifiable, Hashable, Codable {
    let id: String
    var agentID: String
    var taskType: String
    var preferredProviderIDs: [String]
    var fallbackProviderIDs: [String]
    var prefer: String
    var requiredFeatures: [String]
    var maxTokens: Int
    var temperature: Double

    var providerIDs: [String] {
        preferredProviderIDs + fallbackProviderIDs
    }
}

struct LocalAppSettings: Hashable, Codable {
    var libraryMode: String = "single-bundle"
    var autoAnalyzeImports: Bool = true
    var preferredStemEngine: String = "local-stem-planner"
    var preserveOriginalFiles: Bool = true
    var spotifyLinked: Bool = false
    var preferredDownloadSource: String = "local-files"
    var downloadQuality: String = "best"
    var analysisFeatures: [String] = ["bpm", "key", "energy", "chords"]
    var storageRootPath: String = AppConfig.libraryPath
    var debugMode: Bool = false
    var midiBarPosition: String = "bottom"
    var secureTokenService: String = LocalSecureTokenStore.service
}

actor LocalLibraryStore {
    let documentURL: URL

    init(root: URL = AppConfig.libraryURL) {
        documentURL = root.appendingPathComponent("SFA-Library.json")
    }

    func load() throws -> SFALibraryDocument {
        if !FileManager.default.fileExists(atPath: documentURL.path) {
            var seed = SFALibraryDocument.seed
            seed.updatedAt = Date()
            try save(seed)
            return seed
        }

        let data = try Data(contentsOf: documentURL)
        var document = try Self.decoder.decode(SFALibraryDocument.self, from: data)

        if Self.applyMissingDefaults(to: &document) {
            document.updatedAt = Date()
            try save(document)
        }

        return document
    }

    func importAudio(paths: [String]) throws -> (document: SFALibraryDocument, inserted: [TrackSummary]) {
        var document = try load()
        let existingIDs = Set(document.tracks.map(\.id))

        let imported = paths.compactMap { path -> TrackSummary? in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard !existingIDs.contains(url.path) else { return nil }
            return TrackSummary(
                id: url.path,
                title: url.deletingPathExtension().lastPathComponent,
                artist: "Local file",
                source: "Imported",
                bpm: 0,
                key: "Pending",
                stage: "Queued in local store",
                progress: 0.12
            )
        }

        guard !imported.isEmpty else {
            return (document, [])
        }

        document.tracks.insert(contentsOf: imported, at: 0)
        document.processingJobs.insert(
            contentsOf: imported.map { track in
                LocalProcessingJob(
                    id: "import-\(UUID().uuidString)",
                    trackID: track.id,
                    kind: .importAudio,
                    status: .queued,
                    progress: 0.12,
                    detail: "Queued from native file import"
                )
            },
            at: 0
        )
        document.updatedAt = Date()
        try save(document)
        return (document, imported)
    }

    func enqueueProcessing(
        kind: LocalProcessingJob.Kind,
        trackIDs requestedTrackIDs: [String]? = nil
    ) throws -> (document: SFALibraryDocument, jobs: [LocalProcessingJob]) {
        var document = try load()
        let trackIDs = requestedTrackIDs?.filter { id in
            document.tracks.contains { $0.id == id }
        } ?? document.tracks.map(\.id)

        guard !trackIDs.isEmpty else {
            return (document, [])
        }

        let jobs = trackIDs.map { trackID in
            LocalProcessingJob(
                id: "\(kind.rawValue)-\(UUID().uuidString)",
                trackID: trackID,
                kind: kind,
                status: .queued,
                progress: 0.05,
                detail: "\(kind.label) queued in local Swift runtime"
            )
        }

        for trackID in trackIDs {
            guard let index = document.tracks.firstIndex(where: { $0.id == trackID }) else { continue }
            document.tracks[index].stage = "\(kind.label) queued"
            document.tracks[index].progress = max(document.tracks[index].progress, 0.18)
        }

        document.processingJobs.insert(contentsOf: jobs, at: 0)
        document.updatedAt = Date()
        try save(document)
        return (document, jobs)
    }

    func updateProcessingJobs(
        _ jobs: [LocalProcessingJob],
        ensurePlannedStems: Bool = false
    ) throws -> SFALibraryDocument {
        var document = try load()
        for job in jobs {
            guard let index = document.processingJobs.firstIndex(where: { $0.id == job.id }) else { continue }
            document.processingJobs[index] = job
        }
        if ensurePlannedStems {
            insertPlannedStems(for: jobs, into: &document)
        }
        document.updatedAt = Date()
        try save(document)
        return document
    }

    func runAgent(
        agentID: String,
        instruction requestedInstruction: String? = nil
    ) throws -> (document: SFALibraryDocument, task: LocalAgentTask, run: LocalAgentRun) {
        var document = try load()

        guard let agent = document.agentDefinitions.first(where: { $0.id == agentID }) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Unknown local agent \(agentID)"])
        }

        let route = document.providerRoutes.first { $0.agentID == agentID }
        let crate = document.crates.first
        let tracks = Self.selectedTracks(from: document, crate: crate)
        let toolsByID = Dictionary(uniqueKeysWithValues: document.agentTools.map { ($0.id, $0) })
        let toolIDs = agent.defaultToolIDs.filter { toolsByID[$0]?.enabled == true }
        let instruction = requestedInstruction ?? Self.defaultInstruction(for: agent, crate: crate, tracks: tracks)
        let provider = Self.selectProvider(for: route, in: document)
        let now = Date()

        let task = LocalAgentTask(
            id: "agent-task-\(UUID().uuidString)",
            agentID: agent.id,
            instruction: instruction,
            status: .ready,
            trackIDs: tracks.map(\.id),
            crateID: crate?.id,
            toolIDs: toolIDs,
            routeID: route?.id,
            createdAt: now
        )

        let response = Self.buildAgentResponse(
            agent: agent,
            instruction: instruction,
            tracks: tracks,
            crate: crate,
            provider: provider,
            route: route
        )

        let run = LocalAgentRun(
            id: "agent-run-\(UUID().uuidString)",
            taskID: task.id,
            agentID: agent.id,
            providerID: provider?.id,
            model: provider?.defaultModel,
            status: .ready,
            resultSummary: response.summary,
            usage: response.usage,
            output: response.output,
            startedAt: now,
            completedAt: now
        )

        document.agentTasks.insert(task, at: 0)
        document.agentRuns.insert(run, at: 0)
        document.updatedAt = now
        try save(document)

        return (document, task, run)
    }

    func save(_ document: SFALibraryDocument) throws {
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(document)
        try data.write(to: documentURL, options: [.atomic])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func applyMissingDefaults(to document: inout SFALibraryDocument) -> Bool {
        let defaults = SFALibraryDocument.seed
        var changed = false

        if document.schemaVersion < defaults.schemaVersion {
            document.schemaVersion = defaults.schemaVersion
            changed = true
        }

        if document.agentProviders.isEmpty {
            document.agentProviders = defaults.agentProviders
            changed = true
        }
        if document.agentDefinitions.isEmpty {
            document.agentDefinitions = defaults.agentDefinitions
            changed = true
        }
        if document.agentPromptTemplates.isEmpty {
            document.agentPromptTemplates = defaults.agentPromptTemplates
            changed = true
        }
        if document.agentTools.isEmpty {
            document.agentTools = defaults.agentTools
            changed = true
        }
        if document.agentTasks.isEmpty {
            document.agentTasks = defaults.agentTasks
            changed = true
        }
        if document.agentRuns.isEmpty {
            document.agentRuns = defaults.agentRuns
            changed = true
        }
        if document.llmProviders.isEmpty {
            document.llmProviders = defaults.llmProviders
            changed = true
        }
        if document.modelCapabilities.isEmpty {
            document.modelCapabilities = defaults.modelCapabilities
            changed = true
        }
        if document.providerRoutes.isEmpty {
            document.providerRoutes = defaults.providerRoutes
            changed = true
        }

        return changed
    }

    private static func selectedTracks(from document: SFALibraryDocument, crate: LocalCrate?) -> [TrackSummary] {
        let requestedIDs = crate?.trackIDs ?? document.tracks.prefix(2).map(\.id)
        let ordered = requestedIDs.compactMap { id in
            document.tracks.first { $0.id == id }
        }

        if ordered.isEmpty {
            return Array(document.tracks.prefix(2))
        }

        return ordered
    }

    private static func defaultInstruction(
        for agent: LocalAgentDefinition,
        crate: LocalCrate?,
        tracks: [TrackSummary]
    ) -> String {
        switch agent.id {
        case "agent-crate-analyst":
            return "Generate a crate DNA card for \(crate?.name ?? "the current crate")."
        case "agent-mix-planner":
            return "Create a playable set plan from \(tracks.map(\.title).joined(separator: ", "))."
        default:
            return "Analyze \(tracks.map(\.title).joined(separator: ", ")) for BPM, key, energy, and mix compatibility."
        }
    }

    private static func selectProvider(
        for route: LocalProviderRoute?,
        in document: SFALibraryDocument
    ) -> LocalLLMProvider? {
        let providersByID = Dictionary(uniqueKeysWithValues: document.llmProviders.map { ($0.id, $0) })
        var seen = Set<String>()
        let routeIDs = (route?.providerIDs ?? []).filter { seen.insert($0).inserted }
        let routedProviders = routeIDs.compactMap { providersByID[$0] }
        let extraProviders = document.llmProviders
            .sorted { $0.priority < $1.priority }
            .filter { !seen.contains($0.id) }
        let requiredFeatures = Set(route?.requiredFeatures ?? [])
        let candidates = (routedProviders + extraProviders).filter(\.enabled)

        return candidates.first { provider in
            requiredFeatures.isSubset(of: Set(provider.capabilities))
        } ?? candidates.first
    }

    private static func buildAgentResponse(
        agent: LocalAgentDefinition,
        instruction: String,
        tracks: [TrackSummary],
        crate: LocalCrate?,
        provider: LocalLLMProvider?,
        route: LocalProviderRoute?
    ) -> (summary: String, output: [String: LocalJSONValue], usage: [String: Int]) {
        let trackObjects = tracks.map { track in
            LocalJSONValue.object([
                "id": .string(track.id),
                "title": .string(track.title),
                "artist": .string(track.artist),
                "bpm": .integer(track.bpm),
                "key": .string(track.key),
                "stage": .string(track.stage)
            ])
        }
        let bpmValues = tracks.map(\.bpm).filter { $0 > 0 }
        let bpmWindow = tempoWindow(for: bpmValues)
        let providerName = provider?.name ?? "No enabled provider"
        let routeID = route?.id ?? "local-default-route"

        let output: [String: LocalJSONValue]
        let summary: String

        switch agent.id {
        case "agent-crate-analyst":
            let crateName = crate?.name ?? "Current crate"
            summary = "\(crateName) has a \(bpmWindow) performance window with \(tracks.count) locally available track(s) routed through \(providerName)."
            output = [
                "genre_tags": .array([.string("local crate"), .string("sample-forward"), .string("performance-ready")]),
                "era_range": .string("local library"),
                "mood_arc": .string("Warm-up material that can build into a brighter warehouse peak."),
                "dna_summary": .string(summary),
                "suggested_use_cases": .array([.string("warm-up set"), .string("crate prep"), .string("sampler sourcing")]),
                "tracks": .array(trackObjects),
                "route_id": .string(routeID)
            ]
        case "agent-mix-planner":
            let orderedTracks = tracks.sorted { lhs, rhs in
                if lhs.bpm == rhs.bpm {
                    return lhs.title < rhs.title
                }
                return lhs.bpm < rhs.bpm
            }
            summary = "Built a \(orderedTracks.count)-track local set plan over \(bpmWindow) using \(providerName)."
            output = [
                "ordered_tracks": .array(orderedTracks.map { .string($0.title) }),
                "transition_notes": .array([
                    .string("Start with the lowest-tempo record and keep the first transition inside the current crate context."),
                    .string("Use cue-grid and stem records before any external provider call.")
                ]),
                "cue_strategy": .string("Anchor the first drop cue, then use 8 or 16 beat loops for controlled blends."),
                "risk_flags": .array(tracks.isEmpty ? [.string("No local tracks selected")] : []),
                "tracks": .array(trackObjects),
                "route_id": .string(routeID)
            ]
        default:
            let compatibility = compatibilityScore(for: bpmValues)
            let keys = tracks.map(\.key).filter { !$0.isEmpty && $0 != "Pending" }
            let keyCompatible = keys.count <= 1 || Set(keys.map { String($0.suffix(1)) }).count == 1
            summary = "Scored \(tracks.count) track(s) at \(compatibility)% compatibility across \(bpmWindow) using \(providerName)."
            output = [
                "compatibility_score": .integer(compatibility),
                "tempo_match": .string(bpmWindow),
                "key_compatible": .bool(keyCompatible),
                "energy_delta": .number(energyDelta(for: tracks)),
                "mix_notes": .array([
                    .string("Keep analysis local until the user enables a network provider."),
                    .string(keyCompatible ? "Keys are compatible enough for a direct blend." : "Use a drum or stem bridge between keys.")
                ]),
                "tracks": .array(trackObjects),
                "route_id": .string(routeID)
            ]
        }

        let usage = [
            "input_tokens": max(64, instruction.count / 4 + tracks.count * 48),
            "output_tokens": max(48, summary.count / 4 + output.count * 16)
        ]

        return (summary, output, usage)
    }

    private static func tempoWindow(for bpmValues: [Int]) -> String {
        guard let minimum = bpmValues.min(), let maximum = bpmValues.max() else {
            return "pending BPM"
        }

        if minimum == maximum {
            return "\(minimum) BPM"
        }

        return "\(minimum)-\(maximum) BPM"
    }

    private static func compatibilityScore(for bpmValues: [Int]) -> Int {
        guard bpmValues.count > 1 else {
            return 82
        }

        let spread = (bpmValues.max() ?? 0) - (bpmValues.min() ?? 0)
        return max(55, min(98, 96 - spread * 2))
    }

    private static func energyDelta(for tracks: [TrackSummary]) -> Double {
        guard tracks.count > 1 else {
            return 0
        }

        let progressValues = tracks.map(\.progress)
        let spread = (progressValues.max() ?? 0) - (progressValues.min() ?? 0)
        return (spread * 10).rounded() / 10
    }

    private func insertPlannedStems(for jobs: [LocalProcessingJob], into document: inout SFALibraryDocument) {
        let existingIDs = Set(document.stems.map(\.id))
        let stemJobs = jobs.filter { $0.kind == .stems }

        let plannedStems = stemJobs.flatMap { job in
            LocalStem.StemType.defaultSeparationSet.compactMap { type -> LocalStem? in
                let id = "stem-\(job.id)-\(type.rawValue)"
                guard !existingIDs.contains(id) else { return nil }
                return LocalStem(
                    id: id,
                    trackID: job.trackID,
                    processingJobID: job.id,
                    type: type,
                    filePath: nil,
                    fileSize: nil,
                    source: "planned",
                    options: [
                        "engine": .string("local-stem-planner"),
                        "state": .string(job.status.rawValue)
                    ]
                )
            }
        }

        guard !plannedStems.isEmpty else { return }
        document.stems.insert(contentsOf: plannedStems, at: 0)
    }
}
