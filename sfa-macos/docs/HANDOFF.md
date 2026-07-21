# SoundForgeAlchemy macOS Native Handoff

HEAD `41fc1865be3f`

## TL;DR
The macOS app has been rebuilt as a native SwiftUI workbench. Product launch no longer starts Phoenix: UI state, navigation, imports, playback commands, local stores, processing, workflows, agents, UPM progress, showcase IPC/SSE, and chat now have native surfaces.

## PM Plan
- `MAC-001` Native shell and module navigation: passed.
- `MAC-002` Backend adapter and process isolation: passed.
- `MAC-003` Standalone showcase IPC/SSE bridge: passed.
- `MAC-004` Native IPC chat surface: passed.
- `MAC-005` Build and precommit verification: passed.
- `SWIFTPORT-002` Codable local stores: passed for schema-versioned tracks, playlists, stems, jobs, cues, DAW projects, sampler pads, crates, control profiles, provider configuration, and settings.
- `SWIFTPORT-003` Native processing queue: passed for local execution artifacts covering import, download references, stems, analysis, audio-to-MIDI, chord detection, warp maps, cleanup audits, and export manifests.
- `SWIFTPORT-004` Native workflow modules: passed for schema-v3 deck sessions, performance sets, DAW tracks/clips/edit history, controller mappings, sample packs, pad actions, crate track configs, and Big Loopy sets rendered in SwiftUI workbench surfaces.
- `SWIFTPORT-005` Native agent routing: passed for schema-v4 agent definitions, prompt templates, tool schemas, local task/run artifacts, LLM provider records, model capabilities, provider fallback routes, and a SwiftUI agent router surface with deterministic local runs.
- `SWIFTPORT-006` Package readiness: passed for local Swift packaging, signed bundle verification, Developer ID export/notarization readiness inputs, explicit no-Phoenix launch checks, local settings/Keychain token slots, and Settings-surface packaging diagnostics.

## Verification
Latest gates:
- `41fc1865be3f` baseline branchpoint before the native/showcase completion pass.
- `make build` passed for the native macOS project.
- `mix precommit` passed with 4,377 tests and 0 failures after the final hardening pass.
- Latest continuation added local stem persistence and schema-v2 JSON migration; `make build` passed and `mix precommit` passed with 4,403 tests and 0 failures.
- Latest queue continuation added `LocalProcessingEngine`; `make build` passed and `mix precommit` passed with 4,403 tests and 0 failures.
- Latest workflow continuation added schema-v3 native DJ/DAW/MIDI/sampler/crate records and model-driven workbench views; `xcrun swiftc -typecheck ... SoundForgeAlchemy/*.swift` passed. `make build` and direct `xcodebuild` attempts were interrupted because Xcode repeatedly blocked on a locked connected mobile device (`com.apple.mobile.notification_proxy`, device passcode protected) before completing the app build.
- Latest agent continuation added schema-v4 native agent/provider routing records and deterministic local agent runs; `xcrun swiftc -typecheck ... SoundForgeAlchemy/*.swift` passed and `mix precommit` passed with 4,403 tests and 0 failures.
- Latest package-readiness continuation made the development showcase explicit instead of launch-time, added `ExportOptions.plist`, `make verify-package`, direct Swift `make package-local`, a Settings package-readiness panel, local settings diagnostics, and Keychain-backed secure token slots. `make package-local SIGN_IDENTITY="Apple Development: jeremiah@pegues.io (5PZLM9295T)"` produced `build/LocalPackage/Sound Forge Alchemy.app`; `codesign --verify --deep --strict --verbose=2` passed, the bundle identifier is `com.soundforgealchemy.mac`, hardened runtime is enabled, and TeamIdentifier is `XQ4S2X936K`. `security find-identity -v -p codesigning` found the Apple Development identity only, so Developer ID export/notarization is configured for readiness but was not submitted locally.

## Backend Seams
Native routes are placed under the `/api` scope with the `:api_auth` pipeline when they are intended for bearer-token access, because the native app can send `Authorization: Bearer ...` and should not depend on browser CSRF/session cookies. Browser-only endpoints remain under `:browser_api` until they have user-scoped, token-safe ownership checks.
