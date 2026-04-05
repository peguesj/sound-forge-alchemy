import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Audio file drop delegate (US-006)

struct AudioDropDelegate: SwiftUI.DropDelegate {
    // Supported audio UTTypes for macOS 14+
    static let supportedUTTypes: [UTType] = [
        .mp3,
        .audio,
        .wav,
        UTType("public.flac") ?? .audio,
        UTType("public.aac-audio") ?? .audio,
        UTType("com.apple.m4a-audio") ?? .audio,
        UTType("org.xiph.ogg") ?? .audio,
    ]

    // MARK: - Drop validation

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.supportedUTTypes)
    }

    // MARK: - Drop visual indicator

    func dropEntered(info: DropInfo) {
        // Visual feedback is handled by SwiftUI overlay in ContentView
    }

    func dropExited(info: DropInfo) {}

    // MARK: - Handle drop

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: Self.supportedUTTypes)
        guard !providers.isEmpty else { return false }

        var resolvedPaths: [String] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                guard error == nil else { return }

                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let loadedURL = item as? URL {
                    url = loadedURL
                }

                if let validURL = url, validURL.isFileURL {
                    let ext = validURL.pathExtension.lowercased()
                    let allowed = ["mp3", "flac", "wav", "m4a", "aac", "ogg"]
                    if allowed.contains(ext) {
                        resolvedPaths.append(validURL.path)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            guard !resolvedPaths.isEmpty else { return }
            injectDroppedFiles(paths: resolvedPaths)
        }

        return true
    }

    // MARK: - Send paths to Phoenix via WKWebView

    private func injectDroppedFiles(paths: [String]) {
        guard let json = try? JSONSerialization.data(withJSONObject: paths, options: []),
              let jsonString = String(data: json, encoding: .utf8) else { return }

        let js = """
        window.dispatchEvent(new CustomEvent('sfa:files-dropped', {
            detail: { paths: \(jsonString) },
            bubbles: true,
            cancelable: false
        }));
        """
        WebViewStore.shared.evaluate(js)
    }
}

// MARK: - Dock icon drop handler is in AppDelegate (application(_:open:))
// NSApplicationDelegate.application(_:open:) handles files dragged to dock icon
