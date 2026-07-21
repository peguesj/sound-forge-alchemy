# xcconfig — Single-Bundle Runtime

The macOS target now builds as a self-contained Swift app. Debug and Release
configs set `SFA_RUNTIME_MODE = bundled` for build diagnostics, but the app no
longer injects a Phoenix or HTTP server URL through `Info.plist`.

Runtime state is local:

- app storage: `~/Library/Application Support/Sound Forge Alchemy`
- imported media: user-selected file URLs
- development showcase: optional local preview board on `127.0.0.1:4511`

The showcase is a development cockpit for PM progress, IPC, and live testing.
It is not a product runtime dependency and is started explicitly from the
Showcase tab.

Packaging checks:

- `make verify-package` validates Info.plist, entitlements, release signing
  settings, Developer ID export options, and absence of Phoenix launch hooks.
- `make package-local` produces a Release `.app` with an ad-hoc local code
  signature by default. Pass `SIGN_IDENTITY="Apple Development: ..."` or a
  Developer ID identity when local certificate-backed signing is available.
- `make archive` and `make export` use Developer ID release settings and
  `ExportOptions.plist`; notarization still requires Apple credentials.
