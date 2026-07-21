import AppKit
import SwiftUI

// MARK: - AppMenuCommands (SwiftUI scene commands)

struct AppMenuCommands: Commands {
    var body: some Commands {
        // File menu additions
        CommandGroup(replacing: .newItem) {
            Button("Open Audio File…") {
                FilePicker.shared.openPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        // View menu
        CommandMenu("View") {
            Button("Library") {
                NativeCommandCenter.shared.select(.library)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("DJ Tab") {
                NativeCommandCenter.shared.select(.dj)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("DAW Tab") {
                NativeCommandCenter.shared.select(.daw)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Analysis") {
                NativeCommandCenter.shared.select(.pipeline)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Showcase") {
                NativeCommandCenter.shared.select(.showcase)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Playback menu
        CommandMenu("Playback") {
            Button("Play / Pause") {
                NativeCommandCenter.shared.sendPlayback(.playPause)
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Previous Track") {
                NativeCommandCenter.shared.sendPlayback(.previous)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Track") {
                NativeCommandCenter.shared.sendPlayback(.next)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }

        // Tools menu
        CommandMenu("Tools") {
            Button("Stem Separation") {
                NativeCommandCenter.shared.select(.pipeline)
                NativeCommandCenter.shared.runPipeline("stem-separation")
            }

            Button("Analyze Track") {
                NativeCommandCenter.shared.select(.pipeline)
                NativeCommandCenter.shared.runPipeline("analyze-track")
            }

            Button("Run Ready Local Jobs") {
                NativeCommandCenter.shared.select(.pipeline)
                NativeCommandCenter.shared.runPipeline("run-ready")
            }

            Divider()

            Button("Focus Library Search") {
                NativeCommandCenter.shared.select(.library)
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            Button("Toggle Helper Agent") {
                HelperAgentPanel.shared.toggle()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("About Sound Forge Alchemy") {
                AboutViewController.show()
            }
        }
    }
}
