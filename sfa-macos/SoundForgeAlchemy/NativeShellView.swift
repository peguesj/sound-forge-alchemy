import SwiftUI

struct NativeShellView: View {
    @ObservedObject var model: SFAAppModel
    @ObservedObject var showcase: ShowcaseBridge
    @State private var chatDraft = ""

    init(model: SFAAppModel) {
        self.model = model
        self.showcase = model.showcase
    }

    var body: some View {
        HStack(spacing: 0) {
            NativeSidebar(model: model)
            Divider().opacity(0.35)
            VStack(spacing: 0) {
                NativeTopBar(model: model)
                Divider().opacity(0.35)
                ScrollView {
                    content
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(WorkbenchTheme.background)
            }
        }
        .background(WorkbenchTheme.background)
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommandCenter.selectSection)) { notification in
            guard
                let raw = notification.object as? String,
                let section = NativeSection(rawValue: raw)
            else { return }
            model.select(section: section)
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommandCenter.importFiles)) { notification in
            guard let paths = notification.object as? [String] else { return }
            model.handleImportedFiles(paths)
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommandCenter.playback)) { notification in
            guard
                let raw = notification.object as? String,
                let command = PlaybackCommand(rawValue: raw)
            else { return }
            model.handlePlayback(command)
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommandCenter.runPipelineAction)) { notification in
            guard let action = notification.object as? String else { return }
            model.runPipelineAction(action)
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommandCenter.focusShowcaseChat)) { _ in
            model.select(section: .showcase)
            model.requestChatFocus()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedSection {
        case .library:
            LibraryWorkbenchView(model: model)
        case .pipeline:
            PipelineWorkbenchView(model: model)
        case .dj:
            DJWorkbenchView(model: model)
        case .daw:
            DAWWorkbenchView(model: model)
        case .midi:
            MIDIWorkbenchView(model: model)
        case .samples:
            SamplesWorkbenchView(model: model)
        case .agents:
            AgentsWorkbenchView(model: model)
        case .showcase:
            ShowcaseWorkbenchView(model: model, showcase: showcase, chatDraft: $chatDraft)
        case .settings:
            SettingsWorkbenchView(model: model)
        }
    }
}

struct NativeSidebar: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(WorkbenchTheme.accent.opacity(0.18))
                    Image(systemName: "waveform.path")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.accent)
                }
                .frame(width: 42, height: 42)
                Text("Forge")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.primaryText)
            }
            .padding(.top, 18)
            .padding(.bottom, 14)

            ForEach(NativeSection.allCases) { section in
                Button {
                    model.select(section: section)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(section.label)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(width: 66, height: 58)
                    .foregroundStyle(model.selectedSection == section ? WorkbenchTheme.accent : WorkbenchTheme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(model.selectedSection == section ? WorkbenchTheme.accent.opacity(0.16) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.summary)
            }

            Spacer()

            VStack(spacing: 8) {
                Circle()
                    .fill(model.runtime.isReady ? WorkbenchTheme.ready : WorkbenchTheme.warning)
                    .frame(width: 8, height: 8)
                Text(model.runtime.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 82)
        .background(WorkbenchTheme.sidebar)
    }
}

struct NativeTopBar: View {
    @ObservedObject var model: SFAAppModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSection.label)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.primaryText)
                Text(model.selectedSection.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(WorkbenchTheme.secondaryText)
            }

            Spacer()

            ProgressView(value: model.nativeProgress)
                .frame(width: 150)
                .tint(WorkbenchTheme.ready)
                .help("UPM PM-plan progress")

            StatusPill(
                title: model.runtime.isReady ? "Single bundle" : "Indexing bundle",
                systemImage: model.runtime.isReady ? "shippingbox.fill" : "internaldrive",
                tint: model.runtime.isReady ? WorkbenchTheme.ready : WorkbenchTheme.warning
            )

            Button {
                model.refreshBundledRuntime()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh bundled runtime")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(WorkbenchTheme.topbar)
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
    }
}

enum WorkbenchTheme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.085)
    static let sidebar = Color(red: 0.06, green: 0.065, blue: 0.07)
    static let topbar = Color(red: 0.105, green: 0.105, blue: 0.11)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let panelRaised = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let primaryText = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let secondaryText = Color(red: 0.66, green: 0.66, blue: 0.62)
    static let accent = Color(red: 0.20, green: 0.62, blue: 0.78)
    static let ready = Color(red: 0.26, green: 0.74, blue: 0.50)
    static let warning = Color(red: 0.94, green: 0.66, blue: 0.24)
    static let danger = Color(red: 0.88, green: 0.26, blue: 0.33)
    static let violet = Color(red: 0.68, green: 0.46, blue: 0.88)
}

struct WorkbenchPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.primaryText)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WorkbenchTheme.secondaryText)
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(WorkbenchTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06))
        )
    }
}

struct StateBadge: View {
    let state: PipelineState

    var body: some View {
        Text(state.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.13)))
    }

    private var color: Color {
        switch state {
        case .queued: return WorkbenchTheme.secondaryText
        case .running: return WorkbenchTheme.accent
        case .ready: return WorkbenchTheme.ready
        case .warning: return WorkbenchTheme.warning
        case .blocked: return WorkbenchTheme.danger
        }
    }
}
