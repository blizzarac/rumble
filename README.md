# Rumble

Native SwiftUI app for iPhone and iPad (iOS/iPadOS 18+, Swift 6). Design: *Rumble: iOS & iPadOS App Design*.

## Layout

| Path | What |
| --- | --- |
| `Packages/RumbleProto` | `.proto` files and generated gRPC/protobuf code (build plugin) |
| `Packages/RumbleServices` | Domain models, service protocols, fakes, retry/backoff, swipe outbox, SwiftData pantry, timer notifications |
| `Packages/RumbleState` | `@MainActor @Observable` stores: deck, plan/shopping list, cooking, root |
| `Packages/RumbleUI` | SwiftUI views (deck, match, cooking, shopping list; iPhone and iPad layouts) |
| `Rumble/` | App target: entry point and live wiring |
| `project.yml` | XcodeGen spec for the app project |

Layers only talk downwards: views → stores → services → proto. Only the service layer knows about gRPC or SwiftData.

## Status

Written without a Swift toolchain on the machine, then **compiled and tested on GitHub Actions (macOS runner, Xcode 16.4)**: every push builds the packages and the app, runs the unit tests, and runs the UI tests on an iPhone and an iPad simulator. Check the latest run before trusting this list.

Done:
- All four packages, the app target, a widget extension and the XcodeGen spec
- Cook flow end to end: swipe deck → match → step-by-step cooking → pantry updated
- Shop flow: swipe three dinners → shopping list → tick items → pantry filled
- iPad layouts, keyboard shortcuts, VoiceOver actions, haptics
- Live Activity for running cooking timers (Lock Screen and Dynamic Island), mirrored from `CookingStore`
- Local notifications when a timer ends
- SwiftData persistence: pantry, recipe cache, shopping list, swipe queue (swipes survive a relaunch and are sent on the next start)
- Image cache (URLSession memory + disk, shared downloads, prefetch for upcoming cards)
- Auth plumbing: `AuthSession` (token refresh shared between concurrent callers, keychain store), `withDeadline` (2 s swipes, 5 s other calls), `CallPipeline` combining auth, deadline and retry
- gRPC adapters over the generated clients (`RumbleProto`): deck (server streaming), recipes, plans, pantry sync (bidirectional streaming), status codes mapped onto `ServiceError`, keepalive pings
- Unit tests (Swift Testing) for services, stores and the wire mapping; UI tests for the two core flows
- Placeholder app icon

Not done:
- A real sign-in flow and `TokenRefresher` (token type and lifetime still to agree with the backend). For now the token comes from `RUMBLE_TOKEN`
- Pantry stays local: the sync semantics (full state vs changes) are not agreed, so `GRPCPantryService` exists but is not used by the app
- Record a finished dish as cooked / taste profile
- Blurred image placeholders from `image_placeholder`
- Real bundle identifier, signing team and app icon artwork
- Integration tests against a real or in-process gRPC server

## Running against a backend

By default the app uses fake services with sample data. To use the gRPC adapters for the deck, recipes and plans, set these environment variables in the Xcode scheme:

| Variable | Meaning |
| --- | --- |
| `RUMBLE_BACKEND` | `host:port` of the gRPC server |
| `RUMBLE_TOKEN` | access token sent as `authorization: Bearer …` |
| `RUMBLE_TLS` | set to `0` for a plaintext dev server (TLS otherwise) |

## On the Mac

```sh
brew install xcodegen protobuf   # protobuf: the gRPC plugin needs protoc; set PROTOC_PATH=$(which protoc) when building outside CI
# 1. Check the packages build and the tests pass
for p in RumbleServices RumbleState; do (cd Packages/$p && swift test); done
# 2. Check the proto package resolves and generates (verifies package versions and the plugin config)
(cd Packages/RumbleProto && PROTOC_PATH=$(which protoc) swift build)
# 3. Generate the Xcode project
xcodegen generate
# 4. Xcode only sees PROTOC_PATH if it is set for the GUI session, then restart Xcode and open the project
launchctl setenv PROTOC_PATH "$(which protoc)"
open Rumble.xcodeproj
```

On the first build Xcode asks to trust the `GRPCProtobufGenerator` build plugin. Set your team and a real bundle identifier (`project.yml`, three targets: app, widgets, UI tests) before running on a device. The Live Activity needs a real device or a recent simulator.

Notes from getting it to build in CI:
- The generated gRPC types are `internal` (the `visibility` key in `grpc-swift-proto-generator-config.json` has no effect), so the adapters live inside the `RumbleProto` target and nothing else sees `Rumble_V1_*`.
- The plugin only runs `protoc` from `PROTOC_PATH`.
- The grpc-swift 2 repository is `github.com/grpc/grpc-swift` (the old `grpc-swift-2` URL collides with it).
- The generated code produces many deprecation warnings (grpc-swift is moving types around); CI builds the proto package with `-suppress-warnings`.

## Open questions

See the checklist at the end of the design doc (proto repo and versioning, plain gRPC vs Connect, auth, streamed vs paged deck, craving profile, image hosting, household pantry, error handling).
