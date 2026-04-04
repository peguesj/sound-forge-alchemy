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
                WebViewStore.shared.evaluate(
                    "document.querySelector('[data-tab=\"library\"]')?.click()"
                )
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("DJ Tab") {
                WebViewStore.shared.evaluate(
                    "document.querySelector('[data-tab=\"dj\"]')?.click()"
                )
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("DAW Tab") {
                WebViewStore.shared.evaluate(
                    "document.querySelector('[data-tab=\"daw\"]')?.click()"
                )
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Button("Analysis") {
                WebViewStore.shared.evaluate(
                    "document.querySelector('[data-tab=\"analysis\"]')?.click()"
                )
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        // Playback menu
        CommandMenu("Playback") {
            Button("Play / Pause") {
                WebViewStore.shared.evaluate(
                    """
                    (function() {
                        var btn = document.querySelector('[data-action=\"play-pause\"], .play-pause-btn, #play-pause');
                        if (btn) { btn.click(); return; }
                        // Fallback: dispatch custom event for LiveView hook
                        window.dispatchEvent(new CustomEvent('sfa:play-pause'));
                    })();
                    """
                )
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Previous Track") {
                WebViewStore.shared.evaluate(
                    """
                    (function() {
                        var btn = document.querySelector('[data-action=\"prev-track\"], .prev-btn, #prev-track');
                        if (btn) { btn.click(); return; }
                        window.dispatchEvent(new CustomEvent('sfa:prev-track'));
                    })();
                    """
                )
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Next Track") {
                WebViewStore.shared.evaluate(
                    """
                    (function() {
                        var btn = document.querySelector('[data-action=\"next-track\"], .next-btn, #next-track');
                        if (btn) { btn.click(); return; }
                        window.dispatchEvent(new CustomEvent('sfa:next-track'));
                    })();
                    """
                )
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
        }

        // Tools menu
        CommandMenu("Tools") {
            Button("Stem Separation") {
                WebViewStore.shared.evaluate(
                    "window.dispatchEvent(new CustomEvent('sfa:open-stem-separation'))"
                )
            }

            Button("Analyze Track") {
                WebViewStore.shared.evaluate(
                    "window.dispatchEvent(new CustomEvent('sfa:analyze-track'))"
                )
            }

            Divider()

            Button("Focus Library Search") {
                WebViewStore.shared.evaluate(
                    "document.querySelector('[data-search], #library-search, input[placeholder*=\"search\"]')?.focus()"
                )
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
