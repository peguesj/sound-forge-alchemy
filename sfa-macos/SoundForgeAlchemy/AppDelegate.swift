import AppKit
import os.log

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.soundforgealchemy.mac", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions (US-005)
        NotificationManager.shared.requestAuthorization()

        // Set up status bar extra (US-007)
        StatusBarController.shared.setup()

        logger.info("Sound Forge Alchemy launched in single-bundle Swift runtime mode.")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app alive in menu bar even when main window is closed
        return false
    }

    // MARK: Dock icon drag-and-drop (US-006)

    func application(_ sender: NSApplication, open urls: [URL]) {
        let audioExtensions = ["mp3", "flac", "wav", "m4a", "aac", "ogg"]
        let audioURLs = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !audioURLs.isEmpty else { return }

        let paths = audioURLs.map { $0.path }
        NativeCommandCenter.shared.importAudioFiles(paths: paths)
    }
}
