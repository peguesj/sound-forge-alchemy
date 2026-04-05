import AppKit
import os.log

// MARK: - Phoenix Process Manager

final class PhoenixProcessManager {
    static let shared = PhoenixProcessManager()

    private var process: Process?
    private var restartCount = 0
    private let maxRestarts = 3
    private let logger = Logger(subsystem: "com.soundforgealchemy.mac", category: "PhoenixServer")
    private var isShuttingDown = false

    private var sfaPath: String {
        ProcessInfo.processInfo.environment["SFA_PATH"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Developer/sfa")
    }

    private init() {}

    // MARK: - Start

    func start() {
        guard !isShuttingDown else { return }
        guard process == nil || !(process?.isRunning ?? false) else {
            logger.info("Phoenix already running (PID \(self.process?.processIdentifier ?? 0))")
            return
        }

        let mixPath = resolveMixPath()
        guard let mix = mixPath else {
            logger.error("Cannot locate 'mix' binary. Ensure Elixir is installed.")
            showMixNotFoundAlert()
            return
        }

        logger.info("Starting Phoenix at \(self.sfaPath) using mix at \(mix)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: mix)
        proc.arguments = ["phx.server"]
        proc.currentDirectoryURL = URL(fileURLWithPath: sfaPath)

        // Source .env if present
        var env = ProcessInfo.processInfo.environment
        loadDotEnv(into: &env)
        proc.environment = env

        // Pipe stdout → os_log
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        pipeToLog(pipe: stdoutPipe, level: .info)
        pipeToLog(pipe: stderrPipe, level: .error)

        proc.terminationHandler = { [weak self] terminated in
            guard let self, !self.isShuttingDown else { return }
            self.logger.warning("Phoenix exited with code \(terminated.terminationStatus)")
            self.process = nil
            if self.restartCount < self.maxRestarts {
                self.restartCount += 1
                self.logger.info("Restarting Phoenix (attempt \(self.restartCount)/\(self.maxRestarts))…")
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    self.start()
                }
            } else {
                self.logger.error("Phoenix crashed \(self.maxRestarts) times. Showing error.")
                DispatchQueue.main.async {
                    self.showServerCrashedAlert()
                }
            }
        }

        do {
            try proc.run()
            process = proc
            restartCount = 0
            logger.info("Phoenix started (PID \(proc.processIdentifier))")
        } catch {
            logger.error("Failed to launch mix phx.server: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop

    func stop() {
        isShuttingDown = true
        guard let proc = process, proc.isRunning else { return }
        logger.info("Sending SIGTERM to Phoenix (PID \(proc.processIdentifier))")
        proc.terminate()
        // Give it 5 seconds to shut down gracefully
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in
            if proc.isRunning {
                self?.logger.warning("Phoenix still running after SIGTERM, sending SIGKILL")
                proc.interrupt()
            }
        }
        process = nil
    }

    // MARK: - Helpers

    private func resolveMixPath() -> String? {
        // Check common Elixir install paths
        let candidates = [
            "/usr/local/bin/mix",
            "/opt/homebrew/bin/mix",
            "/usr/bin/mix",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.asdf/shims/mix",
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.mise/shims/mix",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func loadDotEnv(into env: inout [String: String]) {
        let envPath = (sfaPath as NSString).appendingPathComponent(".env")
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts.dropFirst().joined(separator: "=")
                .trimmingCharacters(in: .init(charactersIn: "\"' \t"))
            env[key] = value
        }
    }

    private func pipeToLog(pipe: Pipe, level: OSLogType) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            if level == .error {
                self.logger.error("\(line)")
            } else {
                self.logger.info("\(line)")
            }
        }
    }

    private func showMixNotFoundAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Elixir / Mix Not Found"
            alert.informativeText = "Sound Forge Alchemy requires Elixir. Install it via Homebrew:\n\nbrew install elixir"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showServerCrashedAlert() {
        let alert = NSAlert()
        alert.messageText = "Phoenix Server Crashed"
        alert.informativeText = "The Phoenix server crashed \(maxRestarts) times and will not restart automatically. Check Console.app for logs under 'SoundForgeAlchemy'."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions (US-005)
        NotificationManager.shared.requestAuthorization()

        // Set up status bar extra (US-007)
        StatusBarController.shared.setup()

        // Start Phoenix backend
        PhoenixProcessManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PhoenixProcessManager.shared.stop()
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
        let json = (try? JSONSerialization.data(withJSONObject: paths, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        WebViewStore.shared.evaluate("window.dispatchEvent(new CustomEvent('sfa:files-dropped', {detail: {paths: \(json)}}))")
    }
}
