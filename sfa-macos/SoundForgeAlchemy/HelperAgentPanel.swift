import AppKit
import SwiftUI

final class HelperAgentPanel: NSObject {
    static let shared = HelperAgentPanel()

    private var panel: NSPanel?

    private override init() {
        super.init()
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            open()
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func open() {
        if panel == nil {
            buildPanel()
        }

        guard let panel else { return }
        if let screen = NSScreen.main {
            let width: CGFloat = 380
            let height: CGFloat = 360
            let x = screen.visibleFrame.maxX - width - 18
            let y = screen.visibleFrame.midY - height / 2
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        panel.makeKeyAndOrderFront(nil)
    }

    private func buildPanel() {
        let hostingView = NSHostingView(rootView: HelperAgentNativeView {
            HelperAgentPanel.shared.close()
        })

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
    }
}

struct HelperAgentNativeView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("IPC Chat Agent", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            Text("The helper now routes into the native Showcase workspace, where UPM progress, SSE events, and the file-bridged chat agent are visible together.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HelperActionButton(
                    title: "Open Native Showcase",
                    subtitle: "Focus the in-app UPM and IPC chat surface.",
                    systemImage: "chart.xyaxis.line"
                ) {
                    NativeCommandCenter.shared.select(.showcase)
                    onClose()
                }

                HelperActionButton(
                    title: "Open Standalone Board",
                    subtitle: "Open the local SSE/AG-UI board on port 4511.",
                    systemImage: "safari"
                ) {
                    NSWorkspace.shared.open(URL(string: "http://127.0.0.1:4511")!)
                }

                HelperActionButton(
                    title: "Focus Chat",
                    subtitle: "Jump to the native chat composer.",
                    systemImage: "text.bubble"
                ) {
                    NativeCommandCenter.shared.select(.showcase)
                    NativeCommandCenter.shared.focusChat()
                    onClose()
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 360, minHeight: 320)
        .background(.regularMaterial)
    }
}

struct HelperActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
