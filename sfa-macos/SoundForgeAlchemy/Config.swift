import Foundation

/// Build-time configuration injected via xcconfig → Info.plist.
///
/// Usage:
///     let url = AppConfig.serverURL   // http://localhost:4000 (Debug)
///                                     // https://app.soundforgealchemy.com (Release)
enum AppConfig {
    /// Base URL of the SFA Phoenix server.
    /// Sourced from Info.plist key `SFA_SERVER_URL`, which is populated by
    /// `xcconfig/Debug.xcconfig` (local) or `xcconfig/Release.xcconfig` (prod).
    static let serverURL: URL = {
        guard
            let raw = Bundle.main.infoDictionary?["SFA_SERVER_URL"] as? String,
            !raw.isEmpty,
            let url = URL(string: raw)
        else {
            // Fall back to localhost so the app remains runnable in
            // unsigned / simulator builds that skip xcconfig wiring.
            let fallback = URL(string: "http://localhost:4000")!
            #if DEBUG
            print("[AppConfig] SFA_SERVER_URL not set — falling back to \(fallback)")
            #endif
            return fallback
        }
        return url
    }()

    /// Convenience: server URL as a string.
    static var serverURLString: String { serverURL.absoluteString }
}
