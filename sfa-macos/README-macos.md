# Sound Forge Alchemy — macOS Native App

SwiftUI/AppKit native workbench for Sound Forge Alchemy. The product runtime is single-bundle Swift: navigation, imports, local stores, processing queues, DJ/DAW/MIDI/sampler workflows, agents, provider routing, and settings run without launching Phoenix.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+
- Optional: Fastlane and Apple Developer credentials for Developer ID export/notarization

## Quick Start

1. Open in Xcode:
   ```
   cd sfa-macos
   make open
   ```
   or double-click `SoundForgeAlchemy.xcodeproj`

2. Build and run with Cmd+R. The app opens against local Swift runtime state and does not spawn Phoenix.

3. Override the SFA project path:
   ```
   export SFA_PATH=/path/to/your/sfa
   ```

4. Start the development showcase from the Showcase tab only when you want the local PM/IPC board.

## Architecture

| File | Purpose |
|------|---------|
| `SoundForgeAlchemyApp.swift` | `@main` entry, SwiftUI App, scene/commands |
| `ContentView.swift` | Native shell host and drop target |
| `AppState.swift` | Native observable model, PM-plan loader, command handlers |
| `LocalLibraryStore.swift` | Schema-versioned Codable store for tracks, jobs, workflows, agents, providers, and settings |
| `LocalProcessingQueue.swift` | Local queue and artifact writer replacing server job workers |
| `ShowcaseBridge.swift` | Optional development showcase launcher, SSE reader, IPC chat bridge |
| `NativeShellView.swift` | Sidebar, top bar, and native section routing |
| `WorkbenchViews.swift` | Library, pipeline, DJ, DAW, MIDI, samples, agents, showcase, settings surfaces |
| `AppDelegate.swift` | Native launch setup, notifications, status bar, dock drag-and-drop |
| `MenuBarManager.swift` | SwiftUI Commands (File/View/Playback/Tools menus) |
| `NotificationManager.swift` | UserNotifications for job completion |
| `DropDelegate.swift` | NSItemProvider drag-and-drop for audio files |
| `StatusBarController.swift` | NSStatusItem menu bar extra + playback popover |
| `FilePicker.swift` | NSOpenPanel (Cmd+O) file picker → native command bus |
| `AboutViewController.swift` | About panel, reads version from CHANGELOG.md |

## Native Bridges

- `NativeCommandCenter` dispatches menu, playback, file import, pipeline, section, and chat-focus commands.
- `LocalLibraryStore` persists local app state in `~/Library/Application Support/Sound Forge Alchemy`.
- `LocalProcessingQueue` writes deterministic local artifacts for import, download references, stems, analysis, MIDI, chords, warp, cleanup, and export.
- `ShowcaseBridge` can start `tools/showcase/serve.sh` from the Showcase tab for development telemetry; it is not started during product launch.

## Build Targets

```bash
make build    # Debug build → sfa-macos/build/Debug/
make release  # Release build → sfa-macos/build/Release/
make verify-package  # Validate package/signing/no-Phoenix readiness inputs
make package-local   # Build and verify a local signed .app
make package-local SIGN_IDENTITY="Apple Development: Name (TEAMID)"  # Apple Development local signing
make archive  # .xcarchive for distribution → sfa-macos/build/SoundForgeAlchemy.xcarchive
make export   # Export Developer ID .app from archive using ExportOptions.plist
make clean    # Remove all build artefacts
make open     # Open project in Xcode
```

## Bundle Configuration

- **Bundle ID**: `com.soundforgealchemy.mac`
- **Min deployment**: macOS 14.0 (Sonoma)
- **Swift version**: 5.10
- **Hardened Runtime**: enabled
- **Entitlements**: microphone, network client/server, file read/write
- **Developer ID readiness**: `Release.xcconfig`, `ExportOptions.plist`, and Fastlane lanes are configured for Developer ID export and notarization when Apple credentials are available.
