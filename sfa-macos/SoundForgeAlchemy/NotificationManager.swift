import UserNotifications
import AppKit

// MARK: - NotificationManager

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                NSLog("[SFA] Notification permission error: \(error.localizedDescription)")
            } else {
                NSLog("[SFA] Notification permission granted: \(granted)")
            }
        }
    }

    // MARK: - Send Notification

    func send(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[SFA] Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Handle web notifications from Phoenix (via WKWebView message handler)

    func handleWebNotification(_ body: [String: Any]) {
        guard
            let title = body["title"] as? String,
            let message = body["body"] as? String
        else { return }

        // Map Phoenix event types to notification categories
        let type = body["type"] as? String ?? "info"
        let formattedTitle: String
        switch type {
        case "stem_complete":
            formattedTitle = "Stem Separation Complete"
        case "download_complete":
            formattedTitle = "Download Complete"
        case "analysis_complete":
            formattedTitle = "Analysis Complete"
        case "job_complete":
            formattedTitle = "Job Complete"
        default:
            formattedTitle = title
        }

        send(title: formattedTitle, body: message)
    }

    // MARK: - Convenience notification senders

    func notifyStemComplete(trackName: String) {
        send(
            title: "Stem Separation Complete",
            body: "'\(trackName)' stems are ready.",
            identifier: "stem-\(trackName.hashValue)"
        )
    }

    func notifyDownloadComplete(trackName: String) {
        send(
            title: "Download Complete",
            body: "'\(trackName)' has been downloaded.",
            identifier: "download-\(trackName.hashValue)"
        )
    }

    func notifyAnalysisComplete(trackName: String) {
        send(
            title: "Analysis Complete",
            body: "'\(trackName)' analysis is ready.",
            identifier: "analysis-\(trackName.hashValue)"
        )
    }

    // MARK: - APM Formation telemetry (US-A07)
    // Forward notification events to CCEM APM for formation tracking

    func emitToAPM(event: String, title: String, category: String = "notification") {
        let payload: [String: Any] = [
            "type": "info",
            "title": title,
            "message": event,
            "category": category
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "http://127.0.0.1:3032/api/notify") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request).resume()
    }

    /// Emit to APM when a notification fires (fire-and-forget)
    private func sendWithTelemetry(title: String, body: String, identifier: String, category: String) {
        send(title: title, body: body, identifier: identifier)
        emitToAPM(event: body, title: title, category: category)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Allow notifications to appear even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Bring app to foreground when notification is tapped
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        completionHandler()
    }
}
