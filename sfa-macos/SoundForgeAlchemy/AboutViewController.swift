import AppKit

// MARK: - AboutViewController (US-009)

final class AboutViewController {
    static func show() {
        let version = appVersion()
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Sound Forge Alchemy",
            .applicationVersion: version,
            .version: "Build \(buildNumber())",
            .credits: NSAttributedString(
                string: "Professional audio pipeline: stem separation, analysis,\nDJ deck, DAW tools, and Crate Digger.\n\nBuilt with Elixir, Phoenix LiveView, and SwiftUI.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
            .applicationIcon: NSApp.applicationIconImage as Any,
        ]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: - Version helpers

    private static func appVersion() -> String {
        // First try Info.plist marketing version
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return v
        }
        // Fallback: read CHANGELOG.md from SFA project root
        return readChangelogVersion() ?? "5.0.0"
    }

    private static func buildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private static func readChangelogVersion() -> String? {
        let sfaPath = ProcessInfo.processInfo.environment["SFA_PATH"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Developer/sfa")
        let changelogPath = (sfaPath as NSString).appendingPathComponent("CHANGELOG.md")

        guard let content = try? String(contentsOfFile: changelogPath, encoding: .utf8) else {
            return nil
        }

        // Parse first ## [x.y.z] heading from CHANGELOG.md
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## [") {
                let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
                if let end = trimmed[start...].firstIndex(of: "]") {
                    return String(trimmed[start..<end])
                }
            }
        }
        return nil
    }
}
