import AppKit
import SwiftUI

// MARK: - Track info model for status bar popover

struct TrackInfo {
    var title: String = "No track playing"
    var artist: String = ""
    var isPlaying: Bool = false
}

// MARK: - StatusBarController (US-007)

final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var trackInfo = TrackInfo()
    private var eventMonitor: Any?

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Sound Forge Alchemy"
        )
        item.button?.image?.isTemplate = true
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item

        // Build dark-themed popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 300, height: 180)
        pop.behavior = .transient
        pop.animates = true
        let hostingVC = NSHostingController(rootView: StatusBarPopoverView(controller: self))
        hostingVC.view.appearance = NSAppearance(named: .darkAqua)
        pop.contentViewController = hostingVC
        popover = pop

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
    }

    // MARK: - Popover toggle

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            closePopover()
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Update track info from Phoenix (via WKWebView message handler)

    func updateTrackInfo(_ body: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.trackInfo.title = body["title"] as? String ?? "No track playing"
            self.trackInfo.artist = body["artist"] as? String ?? ""
            self.trackInfo.isPlaying = body["isPlaying"] as? Bool ?? false

            // Refresh popover content
            if let pop = self.popover, pop.isShown {
                pop.contentViewController = NSHostingController(
                    rootView: StatusBarPopoverView(controller: self)
                )
            }
        }
    }

    // MARK: - Playback controls

    func playPause() {
        WebViewStore.shared.evaluate(
            "window.dispatchEvent(new CustomEvent('sfa:play-pause'))"
        )
        trackInfo.isPlaying.toggle()
    }

    func previousTrack() {
        WebViewStore.shared.evaluate(
            "window.dispatchEvent(new CustomEvent('sfa:prev-track'))"
        )
    }

    func nextTrack() {
        WebViewStore.shared.evaluate(
            "window.dispatchEvent(new CustomEvent('sfa:next-track'))"
        )
    }

    // MARK: - Accessors for SwiftUI view

    var currentTrackTitle: String { trackInfo.title }
    var currentArtist: String { trackInfo.artist }
    var isPlaying: Bool { trackInfo.isPlaying }
}

// MARK: - Popover SwiftUI view (dark themed)

struct StatusBarPopoverView: View {
    let controller: StatusBarController

    @State private var isPlaying: Bool = false
    @State private var trackTitle: String = "No track playing"
    @State private var artistName: String = ""

    private static let accentColor = Color(red: 0.55, green: 0.2, blue: 0.9)
    private static let bgColor = Color(red: 0.07, green: 0.07, blue: 0.12)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(Self.accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text("Sound Forge Alchemy")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .background(Color.white.opacity(0.1))

            // Album art + track info row
            HStack(spacing: 12) {
                // Album art placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(0.3))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trackTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !artistName.isEmpty {
                        Text(artistName)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // Playback controls
            HStack(spacing: 28) {
                Button(action: { controller.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous track")

                Button(action: {
                    controller.playPause()
                    isPlaying.toggle()
                }) {
                    ZStack {
                        Circle()
                            .fill(Self.accentColor.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Self.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button(action: { controller.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next track")
            }
            .padding(.bottom, 14)
        }
        .frame(width: 300)
        .background(Self.bgColor)
        .onAppear {
            isPlaying = controller.isPlaying
            trackTitle = controller.currentTrackTitle
            artistName = controller.currentArtist
        }
    }
}
