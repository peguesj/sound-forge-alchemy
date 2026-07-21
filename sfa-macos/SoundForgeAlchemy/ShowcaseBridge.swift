import Foundation
import SwiftUI

@MainActor
final class ShowcaseBridge: ObservableObject {
    enum ServiceState: Equatable {
        case stopped
        case starting
        case running(URL)
        case failed(String)
    }

    @Published private(set) var state: ServiceState = .stopped
    @Published private(set) var events: [RuntimeEvent] = []
    @Published private(set) var messages: [ShowcaseMessage] = [
        ShowcaseMessage(
            id: "system-welcome",
            role: .system,
            text: "Showcase bridge ready. Start the IPC board to stream UPM, APM, SSE, and chat events.",
            timestamp: Date()
        )
    ]

    let port: Int = 4511
    let project: String = "sfa-macos"

    private var sseTask: Task<Void, Never>?
    private var chatPollTask: Task<Void, Never>?
    private var seenMessageIDs: Set<String> = ["system-welcome"]
    private var lastChatPollTimestamp = ""
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var serverURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    var eventURL: URL {
        serverURL.appendingPathComponent("api/events")
    }

    var isRunning: Bool {
        if case .running = state {
            return true
        }

        return false
    }

    func start(root: URL) {
        guard case .starting = state else {
            Task { await startIfNeeded(root: root) }
            return
        }
    }

    func stop() {
        sseTask?.cancel()
        sseTask = nil
        chatPollTask?.cancel()
        chatPollTask = nil
        state = .stopped
    }

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(
            ShowcaseMessage(id: UUID().uuidString, role: .user, text: trimmed, timestamp: Date())
        )

        Task {
            var request = URLRequest(url: serverURL.appendingPathComponent("api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": trimmed])

            do {
                _ = try await session.data(for: request)
            } catch {
                await MainActor.run {
                    self.appendEvent(
                        source: "showcase.chat",
                        level: "warning",
                        message: "Unable to post chat message",
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    func pushCard(
        id: String,
        title: String,
        body: String,
        kind: String = "status",
        value: Int? = nil,
        max: Int? = nil,
        items: [[String: String]] = []
    ) {
        guard isRunning else { return }

        Task {
            var request = URLRequest(url: serverURL.appendingPathComponent("api/cards"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payload: [String: Any] = [
                "id": id,
                "kind": kind,
                "title": title,
                "body": body,
                "info": "Pushed from the native macOS app"
            ]
            if let value {
                payload["value"] = value
            }
            if let max {
                payload["max"] = max
            }
            if let value, let max, max > 0 {
                payload["pct"] = Int((Double(value) / Double(max) * 100).rounded())
            }
            if !items.isEmpty {
                payload["items"] = items
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                _ = try await session.data(for: request)
            } catch {
                await MainActor.run {
                    self.appendEvent(
                        source: "showcase.cards",
                        level: "warning",
                        message: "Unable to push showcase card",
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    private func startIfNeeded(root: URL) async {
        if await isHealthy() {
            state = .running(serverURL)
            connectSSE()
            startChatPolling()
            return
        }

        state = .starting
        let scriptURL = root.appendingPathComponent("tools/showcase/serve.sh")
        let showcaseRoot = root.appendingPathComponent("sfa-macos")

        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            state = .failed("Missing executable showcase launcher at \(scriptURL.path)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            "--port", "\(port)",
            "--root", showcaseRoot.path,
            "--project", project,
            "--sources", "handoff,upm,apm,ipc,blocker,mem,agent,decisions"
        ]

        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        for _ in 0..<12 {
            if await isHealthy() {
                state = .running(serverURL)
                appendEvent(source: "showcase", message: "Standalone IPC board is running", detail: serverURL.absoluteString)
                connectSSE()
                startChatPolling()
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        state = .failed("Showcase did not answer on port \(port)")
    }

    private func isHealthy() async -> Bool {
        do {
            let (data, response) = try await session.data(from: serverURL.appendingPathComponent("api/health"))
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(statusCode) && !data.isEmpty
        } catch {
            return false
        }
    }

    private func startChatPolling() {
        chatPollTask?.cancel()
        chatPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollChatOnce()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func pollChatOnce() async {
        guard var components = URLComponents(
            url: serverURL.appendingPathComponent("api/chat/poll"),
            resolvingAgainstBaseURL: false
        ) else { return }

        components.queryItems = [URLQueryItem(name: "since", value: lastChatPollTimestamp)]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawMessages = json["messages"] as? [[String: Any]]
            else { return }

            for rawMessage in rawMessages {
                ingestChatMessage(rawMessage)
            }
        } catch {
            appendEvent(
                source: "showcase.chat",
                level: "warning",
                message: "Unable to poll chat backlog",
                detail: error.localizedDescription
            )
        }
    }

    private func connectSSE() {
        sseTask?.cancel()
        sseTask = Task {
            do {
                let (bytes, _) = try await session.bytes(from: eventURL)
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    guard !payload.isEmpty else { continue }
                    await MainActor.run {
                        self.handleSSEPayload(payload)
                    }
                }
            } catch {
                await MainActor.run {
                    self.appendEvent(
                        source: "showcase.sse",
                        level: "warning",
                        message: "SSE stream disconnected",
                        detail: error.localizedDescription
                    )
                }
            }
        }
    }

    private func handleSSEPayload(_ payload: String) {
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            appendEvent(source: "showcase.sse", message: payload)
            return
        }

        let type = json["type"] as? String ?? "EVENT"
        let name = json["name"] as? String ?? type

        if type.hasPrefix("TEXT_MESSAGE") || name.contains("chat") {
            let text = extractText(from: json)
            if !text.isEmpty {
                let id = json["messageId"] as? String ?? json["id"] as? String
                ingestChatMessage([
                    "id": id ?? UUID().uuidString,
                    "role": "assistant",
                    "text": text,
                    "ts": ISO8601DateFormatter().string(from: Date())
                ])
            }
        }

        appendEvent(
            source: "sse",
            message: name,
            detail: summarize(json)
        )
    }

    private func extractText(from json: [String: Any]) -> String {
        if let text = json["text"] as? String { return text }
        if let value = json["value"] as? [String: Any] {
            return value["text"] as? String ?? value["body"] as? String ?? ""
        }
        if let delta = json["delta"] as? String { return delta }
        return ""
    }

    private func ingestChatMessage(_ raw: [String: Any]) {
        let id = raw["id"] as? String ?? UUID().uuidString
        guard !seenMessageIDs.contains(id) else { return }

        let text = raw["text"] as? String ?? raw["delta"] as? String ?? ""
        guard !text.isEmpty else { return }

        let role = ShowcaseMessage.Role(rawValue: raw["role"] as? String ?? "") ?? .assistant
        let timestampRaw = raw["ts"] as? String ?? raw["timestamp"] as? String ?? ""
        let timestamp = Self.isoDateFormatter.date(from: timestampRaw) ?? Date()

        seenMessageIDs.insert(id)
        messages.append(ShowcaseMessage(id: id, role: role, text: text, timestamp: timestamp))

        if !timestampRaw.isEmpty && timestampRaw > lastChatPollTimestamp {
            lastChatPollTimestamp = timestampRaw
        }
    }

    private func summarize(_ json: [String: Any]) -> String {
        if let value = json["value"] as? [String: Any] {
            if let title = value["title"] as? String { return title }
            if let kind = value["kind"] as? String { return kind }
        }
        if let snapshot = json["snapshot"] as? [String: Any] {
            return "\(snapshot.count) snapshot keys"
        }
        return json.keys.sorted().joined(separator: ", ")
    }

    private func appendEvent(
        source: String,
        level: String = "info",
        message: String,
        detail: String = ""
    ) {
        events.insert(
            RuntimeEvent(source: source, level: level, message: message, detail: detail),
            at: 0
        )
        if events.count > 80 {
            events.removeLast(events.count - 80)
        }
    }

    private static let isoDateFormatter = ISO8601DateFormatter()
}
