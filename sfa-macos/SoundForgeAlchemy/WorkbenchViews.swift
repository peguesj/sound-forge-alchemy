import SwiftUI
import AppKit

struct LibraryWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Library", subtitle: "Local media, crates, playlists, and analysis state live inside the Mac bundle.") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.tracks.count) local track\(model.tracks.count == 1 ? "" : "s")")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WorkbenchTheme.primaryText)
                            Text("Persisted in ~/Library/Application Support/Sound Forge Alchemy")
                                .font(.caption)
                                .foregroundStyle(WorkbenchTheme.secondaryText)
                        }
                        Spacer()
                        Button {
                            FilePicker.shared.openPanel()
                        } label: {
                            Label("Import", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    LazyVStack(spacing: 8) {
                        ForEach(model.tracks) { track in
                            TrackSummaryRow(track: track)
                        }
                    }
                }
            }

            WorkbenchPanel(title: "Local Store Coverage", subtitle: "Codable records replacing Phoenix schemas for the single-bundle port.") {
                LocalStoreCoverageGrid(summary: model.librarySummary)
            }

            PortMapStrip(domains: model.portDomains)
            ModuleGridView(modules: model.modules.filter { ["library", "jobs", "agents"].contains($0.id) })
        }
    }
}

struct PipelineWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Pipeline Console", subtitle: "Single-bundle queue for import, separation, analysis, cueing, and export.") {
                VStack(spacing: 12) {
                    HStack {
                        Button {
                            model.enqueueProcessing(kind: .download)
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                        }
                        Button {
                            model.enqueueProcessing(kind: .stems)
                        } label: {
                            Label("Stems", systemImage: "waveform.path.ecg")
                        }
                        Button {
                            model.enqueueProcessing(kind: .analysis)
                        } label: {
                            Label("Analyze", systemImage: "chart.bar.xaxis")
                        }
                        Button {
                            model.enqueueProcessing(kind: .export)
                        } label: {
                            Label("Export Plan", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            model.runReadyProcessingJobs()
                        } label: {
                            Label("Run Ready", systemImage: "play.fill")
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered)

                    HStack {
                        Button {
                            model.enqueueProcessing(kind: .audioToMIDI)
                        } label: {
                            Label("MIDI", systemImage: "pianokeys")
                        }
                        Button {
                            model.enqueueProcessing(kind: .chordDetection)
                        } label: {
                            Label("Chords", systemImage: "music.quarternote.3")
                        }
                        Button {
                            model.enqueueProcessing(kind: .warp)
                        } label: {
                            Label("Warp", systemImage: "waveform.badge.magnifyingglass")
                        }
                        Button {
                            model.enqueueProcessing(kind: .cleanup)
                        } label: {
                            Label("Cleanup", systemImage: "sparkle.magnifyingglass")
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered)

                    ForEach(model.pipelineStages) { stage in
                        PipelineStageRow(stage: stage)
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                WorkbenchPanel(title: "Bundled Engines", subtitle: "Swift contracts replacing the server-side job modules.") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.processingEngines, id: \.self) { engine in
                            Label(engine, systemImage: "cpu")
                                .foregroundStyle(WorkbenchTheme.primaryText)
                        }
                        Text(model.capabilitySummary)
                            .font(.caption)
                            .foregroundStyle(WorkbenchTheme.secondaryText)
                    }
                }

                WorkbenchPanel(title: "Recent Runtime Events", subtitle: "Native command bus and local runtime checks.") {
                    EventList(events: model.runtimeEvents)
                        .frame(minHeight: 180)
                }
            }

            WorkbenchPanel(title: "Local Processing Jobs", subtitle: "Persisted queue replacing Oban worker state for this port slice.") {
                ProcessingJobList(jobs: model.processingJobs)
                    .frame(minHeight: 180)
            }
        }
    }
}

struct DJWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                ForEach(model.deckSessions) { deck in
                    DeckSessionCard(
                        deck: deck,
                        track: model.tracks.first { $0.id == deck.trackID }
                    )
                }
            }

            WorkbenchPanel(title: "Cue And Performance Sets", subtitle: "Cue grids, stem loops, and chef sets now render from local Swift records.") {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cue grid")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.secondaryText)
                        if model.cuePoints.isEmpty {
                            ContentUnavailableView("No cue points", systemImage: "flag")
                                .frame(maxWidth: .infinity, minHeight: 110)
                        } else {
                            ForEach(model.cuePoints) { cue in
                                Button {
                                    model.appendEvent(source: "dj", message: "Triggered \(cue.label)")
                                } label: {
                                    HStack {
                                        Image(systemName: "flag.fill")
                                        Text(cue.label)
                                        Spacer()
                                        Text("\(Int(cue.seconds))s")
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance sets")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.secondaryText)
                        ForEach(model.performanceSets) { set in
                            PerformanceSetRow(set: set)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ModuleGridView(modules: model.modules.filter { $0.id == "dj" })
        }
    }
}

struct DAWWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Arrangement", subtitle: "Document-style project surface for clips, stems, edit history, and export.") {
                VStack(spacing: 10) {
                    ForEach(model.dawTracks.sorted { $0.position < $1.position }) { track in
                        ArrangementTrackRow(
                            track: track,
                            clips: model.dawClips.filter { $0.trackID == track.id }
                        )
                    }
                }
                .frame(minHeight: 220)
            }

            WorkbenchPanel(title: "Edit History", subtitle: "Crop, fade, gain, and stem operations are native value records.") {
                if model.editOperations.isEmpty {
                    ContentUnavailableView("No edit operations", systemImage: "scissors")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.editOperations) { operation in
                            EditOperationRow(operation: operation)
                        }
                    }
                }
            }

            ModuleGridView(modules: model.modules.filter { $0.id == "daw" || $0.id == "jobs" })
        }
    }
}

struct MIDIWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Control Surface Router", subtitle: "MIDI, OSC, TouchOSC, and device profiles stay in local Swift contracts.") {
                LazyVStack(spacing: 10) {
                    ForEach(model.controlProfiles) { profile in
                        ControlSurfaceRow(
                            name: profile.name,
                            port: "\(profile.transport.rawValue.uppercased()) | \(profile.mappings) mappings",
                            status: .ready
                        )
                    }
                }
            }

            WorkbenchPanel(title: "Native Mapping Table", subtitle: "Controller notes, CCs, channels, and actions replace Phoenix mapping state.") {
                LazyVStack(spacing: 8) {
                    ForEach(model.controlMappings) { mapping in
                        ControlMappingRow(mapping: mapping)
                    }
                }
            }

            ModuleGridView(modules: model.modules.filter { $0.id == "midi" })
        }
    }
}

struct SamplesWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Sample Library", subtitle: "Packs, pads, crate digging, and Big Loopy alchemy sets.") {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(model.samplePacks) { pack in
                            SamplePackTile(pack: pack)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(model.samplerPads) { pad in
                            SamplerPadTile(
                                pad: pad,
                                action: model.padActions.first { $0.padID == pad.id }
                            )
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                WorkbenchPanel(title: "Crate Digging", subtitle: "Per-track crate overrides and stem preferences.") {
                    LazyVStack(spacing: 8) {
                        ForEach(model.crateTrackConfigs) { config in
                            CrateWorkflowRow(
                                config: config,
                                crate: model.crates.first { $0.id == config.crateID },
                                track: model.tracks.first { $0.id == config.trackID }
                            )
                        }
                    }
                }

                WorkbenchPanel(title: "Big Loopy Sets", subtitle: "Alchemy recipes stored as portable local records.") {
                    LazyVStack(spacing: 8) {
                        ForEach(model.bigLoopySets) { set in
                            BigLoopySetRow(set: set)
                        }
                    }
                }
            }

            ModuleGridView(modules: model.modules.filter { ["library", "jobs", "sampler"].contains($0.id) })
        }
    }
}

struct AgentsWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Music Agent Router", subtitle: "Local specialists, prompts, tools, and provider routing run without a Phoenix server.") {
                if model.agentDefinitions.isEmpty {
                    ContentUnavailableView("No local agents", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(model.agentDefinitions) { agent in
                            AgentDefinitionCard(
                                agent: agent,
                                summary: summary(for: agent.id),
                                latestRun: latestRun(for: agent.id),
                                route: route(for: agent.id),
                                onRun: { model.runAgent(agent.id) }
                            )
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 18)], spacing: 18) {
                WorkbenchPanel(title: "Provider Routing", subtitle: "Provider priority, feature requirements, and fallback chains are explicit local records.") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.providerRoutes) { route in
                            ProviderRouteRow(route: route, providers: model.llmProviders)
                        }

                        Divider().opacity(0.5)

                        ForEach(model.llmProviders) { provider in
                            LLMProviderRow(provider: provider)
                        }
                    }
                }

                WorkbenchPanel(title: "Prompt And Tool Contracts", subtitle: "Prompt templates and tool schemas mirror the Phoenix agent contracts in Codable form.") {
                    AgentPromptToolPanel(
                        prompts: model.agentPromptTemplates,
                        tools: model.agentTools
                    )
                }
            }

            WorkbenchPanel(title: "Recent Agent Runs", subtitle: "Deterministic local outputs are persisted as agent tasks and run artifacts.") {
                AgentRunList(
                    runs: model.agentRuns,
                    tasks: model.agentTasks,
                    providers: model.llmProviders,
                    agents: model.agentDefinitions
                )
            }

            ModuleGridView(modules: model.modules.filter { $0.id == "agents" })
        }
    }

    private func summary(for agentID: String) -> AgentSummary? {
        model.agents.first { $0.id == agentID }
    }

    private func latestRun(for agentID: String) -> LocalAgentRun? {
        model.agentRuns
            .filter { $0.agentID == agentID }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private func route(for agentID: String) -> LocalProviderRoute? {
        model.providerRoutes.first { $0.agentID == agentID }
    }
}

struct AgentDefinitionCard: View {
    let agent: LocalAgentDefinition
    let summary: AgentSummary?
    let latestRun: LocalAgentRun?
    let route: LocalProviderRoute?
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(WorkbenchTheme.violet)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(agent.role)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StateBadge(state: summary?.status ?? .queued)
            }

            Text(summary?.lastOutput ?? agent.description)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(3)

            HStack {
                MetadataPill(title: agent.preferredTask.replacingOccurrences(of: "_", with: " "), systemImage: "checklist")
                MetadataPill(title: agent.preferredSpeed, systemImage: "speedometer")
            }

            HStack {
                ForEach(Array(agent.capabilities.prefix(3)), id: \.self) { capability in
                    MetadataPill(title: capability.replacingOccurrences(of: "_", with: " "), systemImage: "bolt.fill")
                }
            }

            HStack {
                MetadataPill(title: route?.id ?? "No route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Button(action: onRun) {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
    }
}

struct ProviderRouteRow: View {
    let route: LocalProviderRoute
    let providers: [LocalLLMProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(WorkbenchTheme.accent)
                Text(route.id)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                MetadataPill(title: route.prefer, systemImage: "slider.horizontal.3")
            }

            Text("Preferred: \(names(for: route.preferredProviderIDs))")
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(1)
            Text("Fallback: \(names(for: route.fallbackProviderIDs))")
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(1)

            HStack {
                MetadataPill(title: route.taskType, systemImage: "checklist")
                MetadataPill(title: "\(route.maxTokens) tokens", systemImage: "text.word.spacing")
                MetadataPill(title: "\(route.requiredFeatures.count) features", systemImage: "bolt.fill")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private func names(for ids: [String]) -> String {
        let providerNames = ids.compactMap { id in
            providers.first { $0.id == id }?.name
        }

        return providerNames.isEmpty ? "none" : providerNames.joined(separator: " -> ")
    }
}

struct LLMProviderRow: View {
    let provider: LocalLLMProvider

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.enabled ? "network" : "pause.circle")
                .foregroundStyle(provider.enabled ? WorkbenchTheme.ready : WorkbenchTheme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(provider.providerType) | \(provider.defaultModel ?? "No default model")")
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            MetadataPill(title: "p\(provider.priority)", systemImage: "number")
            StateBadge(state: provider.pipelineState)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct AgentPromptToolPanel: View {
    let prompts: [LocalAgentPromptTemplate]
    let tools: [LocalAgentTool]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchTheme.secondaryText)
            ForEach(prompts) { prompt in
                AgentPromptRow(prompt: prompt)
            }

            Divider().opacity(0.5)

            Text("Tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchTheme.secondaryText)
            ForEach(tools) { tool in
                AgentToolRow(tool: tool)
            }
        }
    }
}

struct AgentPromptRow: View {
    let prompt: LocalAgentPromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.badge.star")
                    .foregroundStyle(WorkbenchTheme.violet)
                Text(prompt.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                MetadataPill(title: prompt.agentID.replacingOccurrences(of: "agent-", with: ""), systemImage: "person.wave.2")
            }
            Text(prompt.system)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct AgentToolRow: View {
    let tool: LocalAgentTool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.enabled ? "wrench.and.screwdriver.fill" : "wrench.adjustable")
                .foregroundStyle(tool.enabled ? WorkbenchTheme.accent : WorkbenchTheme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            MetadataPill(title: tool.target, systemImage: "internaldrive")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct AgentRunList: View {
    let runs: [LocalAgentRun]
    let tasks: [LocalAgentTask]
    let providers: [LocalLLMProvider]
    let agents: [LocalAgentDefinition]

    var body: some View {
        if runs.isEmpty {
            ContentUnavailableView("No local agent runs", systemImage: "play.square.stack")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(runs.prefix(8)) { run in
                    AgentRunRow(
                        run: run,
                        task: tasks.first { $0.id == run.taskID },
                        provider: run.providerID.flatMap { providerID in
                            providers.first { $0.id == providerID }
                        },
                        agent: agents.first { $0.id == run.agentID }
                    )
                }
            }
        }
    }
}

struct AgentRunRow: View {
    let run: LocalAgentRun
    let task: LocalAgentTask?
    let provider: LocalLLMProvider?
    let agent: LocalAgentDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.square.stack.fill")
                    .foregroundStyle(WorkbenchTheme.ready)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent?.name ?? run.agentID)
                        .font(.system(size: 13, weight: .semibold))
                    Text(task?.instruction ?? run.taskID)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                StateBadge(state: run.status.pipelineState)
            }

            Text(run.resultSummary)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(2)

            HStack {
                MetadataPill(title: provider?.name ?? run.providerID ?? "local", systemImage: "network")
                MetadataPill(title: run.model ?? "default model", systemImage: "cpu")
                MetadataPill(title: "\(run.usage.values.reduce(0, +)) tokens", systemImage: "text.word.spacing")
                MetadataPill(title: run.output.keys.sorted().prefix(3).joined(separator: "/"), systemImage: "curlybraces")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct ShowcaseWorkbenchView: View {
    @ObservedObject var model: SFAAppModel
    @ObservedObject var showcase: ShowcaseBridge
    @Binding var chatDraft: String
    @FocusState private var chatFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
            WorkbenchPanel(title: "UPM Plan Progress", subtitle: "Full Phoenix-to-Swift port plan, mirrored into the showcase board.") {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView(value: model.nativeProgress)
                            .tint(WorkbenchTheme.ready)
                        ForEach(model.pmStories) { story in
                            HStack(spacing: 10) {
                                Image(systemName: story.passed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(story.passed ? WorkbenchTheme.ready : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(story.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("\(story.id) | wave \(story.wave) | \(story.checkpoint)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                WorkbenchPanel(title: "Port Showcase", subtitle: "Development cockpit for this migration; not a product runtime dependency.") {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusPill(title: bridgeLabel, systemImage: bridgeIcon, tint: bridgeTint)
                        Text(showcase.serverURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Start") { showcase.start(root: model.repoRoot) }
                            Button("Open Board") {
                                NSWorkspace.shared.open(showcase.serverURL)
                            }
                            Button("Push Card") { model.pushProgressCard() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
            WorkbenchPanel(title: "SSE Event Feed", subtitle: "Live development events from the local showcase cockpit.") {
                    EventList(events: showcase.events)
                        .frame(minHeight: 260)
                }

                WorkbenchPanel(title: "IPC Chat Agent", subtitle: "File-bridged development chat for the migration board.") {
                    VStack(spacing: 12) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(showcase.messages) { message in
                                    ChatBubble(message: message)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 210)

                        HStack {
                            TextField("Ask about PM progress, blockers, or architecture", text: $chatDraft)
                                .textFieldStyle(.roundedBorder)
                                .focused($chatFieldFocused)
                                .onSubmit(sendChat)
                            Button {
                                sendChat()
                            } label: {
                                Image(systemName: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .onChange(of: model.chatFocusRequest) {
            chatFieldFocused = true
        }
    }

    private var bridgeLabel: String {
        switch showcase.state {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .failed: return "Failed"
        }
    }

    private var bridgeIcon: String {
        switch showcase.state {
        case .running: return "dot.radiowaves.left.and.right"
        case .failed: return "exclamationmark.triangle.fill"
        case .starting: return "hourglass"
        case .stopped: return "pause.circle"
        }
    }

    private var bridgeTint: Color {
        switch showcase.state {
        case .running: return WorkbenchTheme.ready
        case .failed: return WorkbenchTheme.danger
        case .starting: return WorkbenchTheme.warning
        case .stopped: return .secondary
        }
    }

    private func sendChat() {
        showcase.sendChat(chatDraft)
        chatDraft = ""
    }
}

struct SettingsWorkbenchView: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkbenchPanel(title: "Single-Bundle Runtime", subtitle: "The app is being collapsed into local Swift stores, engines, and document models.") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Repository", value: model.repoRoot.path)
                    LabeledContent("Local app storage", value: model.runtime.storageURL.path)
                    LabeledContent("Swift store schema", value: "v\(model.librarySummary.schemaVersion)")
                    LabeledContent("Local records", value: "\(model.librarySummary.totalRecords)")
                    LabeledContent("Runtime status", value: model.runtime.message)
                    LabeledContent("Development showcase", value: model.showcase.serverURL.absoluteString)
                }
            }

            WorkbenchPanel(title: "Local Settings And Identity", subtitle: "Per-user Phoenix settings collapse into local preferences and Keychain-backed secrets.") {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Library mode", value: model.localSettings.libraryMode)
                        LabeledContent("Download source", value: model.localSettings.preferredDownloadSource)
                        LabeledContent("Download quality", value: model.localSettings.downloadQuality)
                        LabeledContent("Stem engine", value: model.localSettings.preferredStemEngine)
                        LabeledContent("MIDI bar", value: model.localSettings.midiBarPosition)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.secureTokenStatus) { token in
                            SecureTokenStatusRow(status: token)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            WorkbenchPanel(title: "Package Readiness", subtitle: "Release checks for a self-contained, signed macOS bundle without a Phoenix launch requirement.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(model.packagingReadiness) { item in
                        PackagingReadinessRow(item: item)
                    }
                }
            }

            WorkbenchPanel(title: "Phoenix To Swift Port Map", subtitle: "Every major Phoenix context now has a Swift destination and migration state.") {
                PortedDomainGrid(domains: model.portDomains)
            }
        }
    }
}

struct SecureTokenStatusRow: View {
    let status: LocalSecureTokenStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.present ? "key.fill" : "key")
                .foregroundStyle(status.present ? WorkbenchTheme.ready : WorkbenchTheme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.account)
                    .font(.system(size: 13, weight: .semibold))
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }
            Spacer()
            StateBadge(state: status.present ? .ready : .queued)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct PackagingReadinessRow: View {
    let item: PackagingReadinessItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    StateBadge(state: item.state)
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private var color: Color {
        switch item.state {
        case .ready: return WorkbenchTheme.ready
        case .warning: return WorkbenchTheme.warning
        case .blocked: return WorkbenchTheme.danger
        case .running: return WorkbenchTheme.accent
        case .queued: return WorkbenchTheme.secondaryText
        }
    }
}

struct PipelineStageRow: View {
    let stage: PipelineStage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stage.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stage.name).fontWeight(.semibold)
                    StateBadge(state: stage.state)
                }
                Text(stage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: stage.progress)
                    .tint(stage.state == .ready ? WorkbenchTheme.ready : WorkbenchTheme.accent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct ModuleGridView: View {
    let modules: [FeatureModule]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(modules) { module in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(module.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(WorkbenchTheme.primaryText)
                        Spacer()
                        StateBadge(state: module.status)
                    }
                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                    Divider()
                    LabeledContent("Owner", value: module.owner)
                    LabeledContent("Native surface", value: module.nativeSurface)
                }
                .font(.system(size: 12))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panel))
            }
        }
    }
}

struct TrackSummaryRow: View {
    let track: TrackSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(WorkbenchTheme.accent.opacity(0.14))
                Image(systemName: "waveform")
                    .foregroundStyle(WorkbenchTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.primaryText)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }
            .frame(minWidth: 160, alignment: .leading)

            MetadataPill(title: track.source, systemImage: "folder")
            MetadataPill(title: track.bpm == 0 ? "BPM pending" : "\(track.bpm) BPM", systemImage: "metronome")
            MetadataPill(title: track.key, systemImage: "music.note")

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(track.stage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WorkbenchTheme.primaryText)
                ProgressView(value: track.progress)
                    .frame(width: 120)
                    .tint(WorkbenchTheme.accent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
    }
}

struct MetadataPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(WorkbenchTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }
}

struct PortMapStrip: View {
    let domains: [PortedDomain]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(domains.prefix(4)) { domain in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: icon(for: domain.status))
                            .foregroundStyle(color(for: domain.status))
                        Spacer()
                        StateBadge(state: domain.status.pipelineState)
                    }
                    Text(domain.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.primaryText)
                    Text(domain.swiftTarget)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
            }
        }
    }

    private func icon(for status: PortedDomain.Status) -> String {
        switch status {
        case .native: return "checkmark.seal.fill"
        case .porting: return "arrow.triangle.2.circlepath"
        case .planned: return "circle.dashed"
        }
    }

    private func color(for status: PortedDomain.Status) -> Color {
        switch status {
        case .native: return WorkbenchTheme.ready
        case .porting: return WorkbenchTheme.accent
        case .planned: return WorkbenchTheme.secondaryText
        }
    }
}

struct PortedDomainGrid: View {
    let domains: [PortedDomain]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
            ForEach(domains) { domain in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(domain.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.primaryText)
                        Spacer()
                        StateBadge(state: domain.status.pipelineState)
                    }

                    Text(domain.notes)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("From", value: domain.sourceModules.joined(separator: ", "))
                        LabeledContent("To", value: domain.swiftTarget)
                    }
                    .font(.caption)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
            }
        }
    }
}

struct LocalStoreCoverageGrid: View {
    let summary: LocalLibrarySummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(summary.domains) { domain in
                HStack(spacing: 10) {
                    Image(systemName: domain.systemImage)
                        .foregroundStyle(domain.count > 0 ? WorkbenchTheme.accent : WorkbenchTheme.secondaryText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(domain.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.primaryText)
                        Text("\(domain.count) record\(domain.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(WorkbenchTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(WorkbenchTheme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
            }
        }
    }
}

struct ProcessingJobList: View {
    let jobs: [LocalProcessingJob]

    var body: some View {
        if jobs.isEmpty {
            ContentUnavailableView("No local jobs yet", systemImage: "tray")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(jobs.prefix(12)) { job in
                    ProcessingJobRow(job: job)
                }
            }
        }
    }
}

struct ProcessingJobRow: View {
    let job: LocalProcessingJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.kind.systemImage)
                .foregroundStyle(WorkbenchTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.kind.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.primaryText)
                Text(job.detail)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                    .lineLimit(1)
                if let outputPath = job.outputPath {
                    Text(outputPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            ProgressView(value: job.progress)
                .frame(width: 90)
                .tint(WorkbenchTheme.accent)
            StateBadge(state: job.status.pipelineState)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct EventList: View {
    let events: [RuntimeEvent]

    var body: some View {
        if events.isEmpty {
            ContentUnavailableView("No events yet", systemImage: "dot.radiowaves.left.and.right")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(events) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Text(event.timeLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(event.source)
                                        .font(.caption.weight(.semibold))
                                    Text(event.level)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(event.level == "warning" ? WorkbenchTheme.warning : .secondary)
                                }
                                Text(event.message)
                                    .font(.system(size: 12))
                                if !event.detail.isEmpty {
                                    Text(event.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
                    }
                }
            }
        }
    }
}

struct DeckSessionCard: View {
    let deck: LocalDeckSession
    let track: TrackSummary?

    var body: some View {
        WorkbenchPanel(title: deck.name, subtitle: track?.title ?? deck.trackID) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(deckColor.opacity(0.18), lineWidth: 16)
                    Circle().trim(from: 0.0, to: deck.isPlaying ? 0.78 : 0.42)
                        .stroke(deckColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", deck.bpm))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("BPM | \(deck.key)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 166, height: 166)

                HStack {
                    StateBadge(state: deck.isPlaying ? .running : .queued)
                    MetadataPill(title: "\(deck.loopLengthBeats) beat loop", systemImage: "repeat")
                    MetadataPill(title: String(format: "%+.1f%%", deck.pitch), systemImage: "slider.horizontal.3")
                }

                VStack(spacing: 6) {
                    ForEach(deck.stemLevels.sorted { $0.key < $1.key }, id: \.key) { stem in
                        HStack {
                            Text(stem.key.capitalized)
                                .font(.caption.weight(.medium))
                                .frame(width: 54, alignment: .leading)
                            ProgressView(value: stem.value)
                                .tint(deckColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var deckColor: Color {
        deck.deck == "A" ? WorkbenchTheme.accent : WorkbenchTheme.violet
    }
}

struct PerformanceSetRow: View {
    let set: LocalPerformanceSet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.3.group.fill")
                    .foregroundStyle(WorkbenchTheme.violet)
                Text(set.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                MetadataPill(title: set.mode.replacingOccurrences(of: "_", with: " "), systemImage: "slider.horizontal.below.rectangle")
            }
            Text(set.notes)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
            HStack {
                MetadataPill(title: "\(set.deckSessionIDs.count) decks", systemImage: "headphones")
                MetadataPill(title: "\(set.cuePointIDs.count) cues", systemImage: "flag")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct ArrangementTrackRow: View {
    let track: LocalDAWTrack
    let clips: [LocalDAWClip]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(track.trackType)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }
            .frame(width: 86, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.10))
                    ForEach(clips) { clip in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(trackColor.opacity(clip.muted ? 0.28 : 0.75))
                            .frame(
                                width: max(34, proxy.size.width * CGFloat(clip.lengthBeats / 64)),
                                height: 24
                            )
                            .offset(x: proxy.size.width * CGFloat(clip.startBeat / 64))
                    }
                }
            }
            .frame(height: 28)

            Text("\(clips.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .frame(width: 22)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private var trackColor: Color {
        switch track.position % 4 {
        case 0: return WorkbenchTheme.violet
        case 1: return WorkbenchTheme.warning
        case 2: return WorkbenchTheme.ready
        default: return WorkbenchTheme.accent
        }
    }
}

struct EditOperationRow: View {
    let operation: LocalEditOperation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "scissors")
                .foregroundStyle(WorkbenchTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(operation.operationType.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Text(operation.stemID ?? "Project operation")
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            MetadataPill(title: "Beat \(Int(operation.position))", systemImage: "metronome")
            if !operation.params.isEmpty {
                MetadataPill(title: operation.params.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", "), systemImage: "curlybraces")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct ControlMappingRow: View {
    let mapping: LocalControlMapping

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mapping.midiType == "cc" ? "slider.horizontal.3" : "circle.grid.3x3.fill")
                .foregroundStyle(WorkbenchTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(mapping.action.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Text(mapping.deviceName)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }
            Spacer()
            MetadataPill(title: mapping.midiType.uppercased(), systemImage: "cable.connector")
            MetadataPill(title: "Ch \(mapping.channel) | \(mapping.number)", systemImage: "number")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct SamplePackTile: View {
    let pack: LocalSamplePack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(WorkbenchTheme.accent)
                Spacer()
                StateBadge(state: pack.status == "ready" ? .ready : .queued)
            }
            Text(pack.name)
                .font(.system(size: 13, weight: .semibold))
            Text("\(pack.category.capitalized) | \(pack.bpmMin)-\(pack.bpmMax) BPM | \(pack.totalFiles) files")
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct SamplerPadTile: View {
    let pad: LocalSamplerPad
    let action: LocalPadAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(pad.index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WorkbenchTheme.secondaryText)
                Spacer()
                Image(systemName: pad.stemID == nil ? "waveform" : "waveform.path.ecg")
                    .foregroundStyle(WorkbenchTheme.accent)
            }
            Text(pad.label)
                .font(.system(size: 13, weight: .semibold))
            ProgressView(value: pad.volume)
                .tint(WorkbenchTheme.accent)
            Text(action?.trigger ?? "No trigger")
                .font(.caption2)
                .foregroundStyle(WorkbenchTheme.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct CrateWorkflowRow: View {
    let config: LocalCrateTrackConfig
    let crate: LocalCrate?
    let track: TrackSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note.house.fill")
                    .foregroundStyle(WorkbenchTheme.ready)
                Text(crate?.name ?? config.crateID)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                MetadataPill(title: track?.key ?? "Key", systemImage: "music.note")
            }
            Text(track?.title ?? config.trackID)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
            Text(config.stemOverride.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct BigLoopySetRow: View {
    let set: LocalBigLoopySet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "loop")
                    .foregroundStyle(WorkbenchTheme.violet)
                Text(set.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                StateBadge(state: set.status == "complete" ? .ready : .queued)
            }
            HStack {
                MetadataPill(title: set.type.replacingOccurrences(of: "_", with: " "), systemImage: "rectangle.3.group")
                MetadataPill(title: set.outputFormat.replacingOccurrences(of: "_", with: " "), systemImage: "square.and.arrow.up")
            }
            Text(set.recipe.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.secondaryText)
                .lineLimit(2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

private extension LocalJSONValue {
    var displayString: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(format: "%.2f", value)
        case let .integer(value):
            return "\(value)"
        case let .bool(value):
            return value ? "true" : "false"
        case let .object(value):
            return value.keys.sorted().joined(separator: "/")
        case let .array(value):
            return value.map(\.displayString).joined(separator: "/")
        case .null:
            return "null"
        }
    }
}

struct DeckPanel: View {
    let title: String
    let bpm: String
    let key: String
    let color: Color

    var body: some View {
        WorkbenchPanel(title: title, subtitle: "Native deck controls") {
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(color.opacity(0.18), lineWidth: 18)
                    Circle().trim(from: 0.0, to: 0.72)
                        .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack {
                        Text(bpm).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("BPM | \(key)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 190, height: 190)
                HStack {
                    Button { NativeCommandCenter.shared.sendPlayback(.previous) } label: { Image(systemName: "backward.fill") }
                    Button { NativeCommandCenter.shared.sendPlayback(.playPause) } label: { Image(systemName: "playpause.fill") }
                    Button { NativeCommandCenter.shared.sendPlayback(.next) } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct TimelineLane: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.10))
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.75))
                    .frame(width: proxy.size.width * 0.46)
                    .offset(x: proxy.size.width * 0.18)
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.40))
                    .frame(width: proxy.size.width * 0.20)
                    .offset(x: proxy.size.width * 0.68)
            }
        }
        .frame(height: 28)
    }
}

struct ControlSurfaceRow: View {
    let name: String
    let port: String
    let status: PipelineState

    var body: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(WorkbenchTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.semibold)
                Text(port).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StateBadge(state: status)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct ChatBubble: View {
    let message: ShowcaseMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 12))
                .padding(10)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(message.role == .user ? WorkbenchTheme.accent : Color.secondary.opacity(0.10))
                )
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}
