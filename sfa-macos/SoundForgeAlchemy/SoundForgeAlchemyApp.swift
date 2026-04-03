import SwiftUI
import AppKit

@main
struct SoundForgeAlchemyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Sound Forge Alchemy") {
            ContentView()
                .frame(minWidth: 1024, minHeight: 768)
                .background(Color(red: 0.05, green: 0.05, blue: 0.09))
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppMenuCommands()

            // Helper Agent panel toggle (Cmd+Shift+H)
            CommandMenu("Agent") {
                Button("Toggle Helper Agent") {
                    HelperAgentPanel.shared.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Customize NSWindow after it becomes available

    private func configureWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            applyCustomChrome(to: window)
        }
    }

    private func applyCustomChrome(to window: NSWindow) {
        // Remove standard macOS title bar chrome
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // Dark background matching the SFA palette
        window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)

        // Enable vibrancy behind the tab strip
        if let contentView = window.contentView {
            let vfxView = NSVisualEffectView()
            vfxView.material = .sidebar
            vfxView.state = .active
            vfxView.blendingMode = .behindWindow
            vfxView.frame = NSRect(x: 0, y: 0, width: 64, height: contentView.bounds.height)
            vfxView.autoresizingMask = [.height]
            contentView.addSubview(vfxView, positioned: .below, relativeTo: contentView.subviews.first)
        }

        // Full-screen capable
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        // Minimum size
        window.minSize = NSSize(width: 1024, height: 768)
    }
}
