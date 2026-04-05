# Sound Forge Alchemy — macOS Native App

SwiftUI/AppKit wrapper for the Sound Forge Alchemy Phoenix application.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+
- Elixir + Phoenix installed (for the backend server)

## Quick Start

1. Open in Xcode:
   ```
   cd sfa-macos
   make open
   ```
   or double-click `SoundForgeAlchemy.xcodeproj`

2. Build and run with Cmd+R. The app auto-starts `mix phx.server` from `~/Developer/sfa`.

3. Override the SFA project path:
   ```
   export SFA_PATH=/path/to/your/sfa
   ```

## Architecture

| File | Purpose |
|------|---------|
| `SoundForgeAlchemyApp.swift` | `@main` entry, SwiftUI App, scene/commands |
| `ContentView.swift` | WKWebView container, JS bridge, drop target |
| `AppDelegate.swift` | Phoenix process manager, dock drag-and-drop |
| `MenuBarManager.swift` | SwiftUI Commands (File/View/Playback/Tools menus) |
| `NotificationManager.swift` | UserNotifications for job completion |
| `DropDelegate.swift` | NSItemProvider drag-and-drop for audio files |
| `StatusBarController.swift` | NSStatusItem menu bar extra + playback popover |
| `FilePicker.swift` | NSOpenPanel (Cmd+O) file picker → Phoenix bridge |
| `AboutViewController.swift` | About panel, reads version from CHANGELOG.md |

## Phoenix JS Bridge

The app injects `window.sfaNative` into the Phoenix web context:

```javascript
// From Phoenix LiveView JS hooks — send native notification
window.sfaNative.postNotification("Stem Complete", "track.mp3 is ready");

// Update status bar track info
window.sfaNative.updateTrackInfo({ title: "Track Name", artist: "Artist", isPlaying: true });
```

Native events dispatched to `window`:
- `sfa:files-dropped` — audio files dragged onto window or dock icon
- `sfa:files-selected` — audio files chosen via Cmd+O open panel
- `sfa:play-pause` — triggered by menu bar or status bar
- `sfa:prev-track` / `sfa:next-track` — triggered by menu bar or status bar

## Build Targets

```bash
make build    # Debug build → sfa-macos/build/Debug/
make release  # Release build → sfa-macos/build/Release/
make archive  # .xcarchive for distribution → sfa-macos/build/SoundForgeAlchemy.xcarchive
make clean    # Remove all build artefacts
make open     # Open project in Xcode
```

## Bundle Configuration

- **Bundle ID**: `com.soundforgealchemy.mac`
- **Min deployment**: macOS 14.0 (Sonoma)
- **Swift version**: 5.10
- **Hardened Runtime**: enabled (app-sandbox disabled for localhost access)
- **Entitlements**: microphone, network client/server, file read/write
