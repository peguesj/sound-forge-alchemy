import AppKit
import SwiftUI
import WebKit

// MARK: - Helper Agent floating panel (Cmd+Shift+H)

final class HelperAgentPanel: NSObject {
    static let shared = HelperAgentPanel()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private let helperURL = URL(string: "http://127.0.0.1:4000/agent-chat")!

    private override init() {
        super.init()
    }

    // MARK: - Toggle

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    // MARK: - Open panel

    private func open() {
        if panel == nil {
            buildPanel()
        }
        guard let panel else { return }

        // Position at right edge of screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let sh = screen.visibleFrame.height
            let w: CGFloat = 360
            let h: CGFloat = 540
            let x = screen.visibleFrame.minX + sw - w - 16
            let y = screen.visibleFrame.minY + (sh - h) / 2
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        panel.makeKeyAndOrderFront(nil)
        webView?.load(URLRequest(url: helperURL))
    }

    // MARK: - Close panel

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: - Build panel

    private func buildPanel() {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.websiteDataStore = WKWebsiteDataStore.default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.layer?.cornerRadius = 12
        wv.layer?.masksToBounds = true
        self.webView = wv

        let hostView = NSHostingView(rootView:
            HelperAgentPanelChrome(webView: wv) {
                HelperAgentPanel.shared.close()
            }
        )

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 540),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 0.96)
        p.appearance = NSAppearance(named: .darkAqua)
        p.contentView = hostView
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = p
    }
}

// MARK: - SwiftUI chrome for the panel

struct HelperAgentPanelChrome: NSViewRepresentable {
    let webView: WKWebView
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1).cgColor

        // Drag handle bar
        let handle = NSView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        handle.layer?.cornerRadius = 2
        container.addSubview(handle)

        // WKWebView
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            handle.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),

            webView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
