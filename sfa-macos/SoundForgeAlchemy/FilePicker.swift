import AppKit
import UniformTypeIdentifiers

// MARK: - FilePicker (US-008)

final class FilePicker {
    static let shared = FilePicker()

    private init() {}

    // MARK: - Open panel (Cmd+O)

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Audio Files"
        panel.prompt = "Open"
        panel.message = "Select audio files to import into Sound Forge Alchemy"

        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedContentTypes

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let paths = panel.urls.map { $0.path }
            self?.sendPathsToNativeRuntime(paths)
        }
    }

    // MARK: - Supported audio content types

    private var supportedContentTypes: [UTType] {
        [
            .mp3,
            .wav,
            .audio,
            UTType("public.flac") ?? .audio,
            UTType("public.aac-audio") ?? .audio,
            UTType("com.apple.m4a-audio") ?? .audio,
            UTType("org.xiph.ogg") ?? .audio,
        ].compactMap { $0 }
    }

    // MARK: - Send selected file paths to the native command bus

    private func sendPathsToNativeRuntime(_ paths: [String]) {
        NativeCommandCenter.shared.importAudioFiles(paths: paths)
    }
}
