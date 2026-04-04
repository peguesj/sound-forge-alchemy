import SwiftUI
import WebKit
import AppKit

// MARK: - WKWebView coordinator handling JS messages and navigation

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var parent: WebViewRepresentable

    init(_ parent: WebViewRepresentable) {
        self.parent = parent
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.parent.isLoading = true
            self.parent.hasError = false
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.parent.isLoading = false
            self.parent.hasError = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.parent.isLoading = false
            self.parent.hasError = true
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        DispatchQueue.main.async {
            self.parent.isLoading = false
            self.parent.hasError = true
        }
    }

    // MARK: WKScriptMessageHandler — receives messages from Phoenix web app

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "sfaNotification":
            NotificationManager.shared.handleWebNotification(body)
        case "sfaTrackInfo":
            StatusBarController.shared.updateTrackInfo(body)
        case "sfaFileDropped":
            // Echo dropped files back to the web layer is handled by DropDelegate
            break
        default:
            break
        }
    }
}

// MARK: - NSViewRepresentable wrapping WKWebView

struct WebViewRepresentable: NSViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var hasError: Bool

    static let phoenixURL = URL(string: "http://127.0.0.1:4000")!

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Enable JavaScript
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Allow localStorage via non-persistent data store (use default for persistence)
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Register JS message handlers for native bridge
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "sfaNotification")
        contentController.add(context.coordinator, name: "sfaTrackInfo")
        contentController.add(context.coordinator, name: "sfaFileDropped")

        // Inject bridge script that Phoenix can use to send native messages
        let bridgeScript = WKUserScript(
            source: """
            window.sfaNative = {
                postNotification: function(title, body) {
                    window.webkit.messageHandlers.sfaNotification.postMessage({title: title, body: body});
                },
                updateTrackInfo: function(info) {
                    window.webkit.messageHandlers.sfaTrackInfo.postMessage(info);
                },
                notifyFileDropped: function(paths) {
                    window.webkit.messageHandlers.sfaFileDropped.postMessage({paths: paths});
                }
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Store reference for menu/status bar access
        WebViewStore.shared.webView = webView

        // Load Phoenix app
        let request = URLRequest(
            url: Self.phoenixURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        webView.load(request)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No dynamic updates needed; URL is fixed at http://127.0.0.1:4000
    }
}

// MARK: - Shared WebView reference for JS evaluation from menus/status bar

final class WebViewStore {
    static let shared = WebViewStore()
    weak var webView: WKWebView?

    private init() {}

    /// Evaluate arbitrary JS in the Phoenix web context
    func evaluate(_ js: String, completion: ((Any?, Error?) -> Void)? = nil) {
        webView?.evaluateJavaScript(js, completionHandler: completion)
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @State private var isLoading = true
    @State private var hasError = false
    @State private var retryCount = 0
    @SceneStorage("selectedTab") private var selectedTabRaw: String = SFATab.library.rawValue
    @State private var isDragTarget = false

    private let maxRetries = 3
    private static let bgColor = Color(red: 0.05, green: 0.05, blue: 0.09)

    private var selectedTab: SFATab {
        SFATab(rawValue: selectedTabRaw) ?? .library
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left custom tab strip
            SFATabStrip(
                selectedTab: Binding(
                    get: { selectedTab },
                    set: { selectedTabRaw = $0.rawValue }
                ),
                onSelect: { tab in
                    WebViewStore.shared.evaluate(tab.navigationJS)
                }
            )

            // Main web content area
            ZStack {
                Self.bgColor.ignoresSafeArea()

                WebViewRepresentable(isLoading: $isLoading, hasError: $hasError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(hasError ? 0 : 1)

                // Drop zone overlay
                if isDragTarget {
                    dropZoneOverlay
                }

                if isLoading && !hasError {
                    loadingOverlay
                }

                if hasError {
                    errorOverlay
                }
            }
        }
        .background(Self.bgColor)
        .onDrop(
            of: AudioDropDelegate.supportedUTTypes,
            delegate: DropDelegateWithHover(
                inner: AudioDropDelegate(),
                onEnter: { isDragTarget = true },
                onExit:  { isDragTarget = false }
            )
        )
    }

    // MARK: Drop zone overlay

    private var dropZoneOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(red: 0.55, green: 0.2, blue: 0.9))
                    .symbolEffect(.pulse)

                Text("Drop audio files here")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("MP3 · FLAC · WAV · M4A · AAC · OGG")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Self.bgColor.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "waveform")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(red: 0.55, green: 0.2, blue: 0.9))
                    .symbolEffect(.variableColor.iterative.reversing)

                Text("Sound Forge Alchemy")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(red: 0.55, green: 0.2, blue: 0.9))
                    .scaleEffect(0.85)

                Text("Starting Phoenix server…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Error overlay

    private var errorOverlay: some View {
        ZStack {
            Self.bgColor.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Cannot connect to Sound Forge Alchemy")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("The Phoenix server at http://127.0.0.1:4000 is not responding.\nEnsure the server is running with `mix phx.server`.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                HStack(spacing: 12) {
                    Button("Retry") {
                        retryLoad()
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    Button("Open Terminal") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.55, green: 0.2, blue: 0.9))
            }
        }
    }

    private func retryLoad() {
        guard retryCount < maxRetries else { return }
        retryCount += 1
        hasError = false
        isLoading = true
        WebViewStore.shared.webView?.reload()
    }
}

// MARK: - Drop delegate with hover callbacks

struct DropDelegateWithHover: SwiftUI.DropDelegate {
    let inner: AudioDropDelegate
    let onEnter: () -> Void
    let onExit: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        inner.validateDrop(info: info)
    }

    func dropEntered(info: DropInfo) {
        onEnter()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        onExit()
        return inner.performDrop(info: info)
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 800)
}
