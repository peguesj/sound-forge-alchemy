import SwiftUI
import AppKit

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject private var model = SFAAppModel()
    @State private var isDragTarget = false

    private static let bgColor = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        ZStack {
            NativeShellView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDragTarget {
                dropZoneOverlay
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
            Color.black.opacity(0.42).ignoresSafeArea()

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
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
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
