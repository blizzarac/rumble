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

Written on a Linux machine with **no Swift toolchain, so none of it has been compiled or run yet**. Expect a round of small compile fixes (Swift 6 strict concurrency especially).

Done:
- All four packages, the app target and the XcodeGen spec
- Cook flow end to end on fake data: swipe deck → match → step-by-step cooking → pantry updated
- Shop flow: swipe three dinners → shopping list → tick items → pantry filled
- Retry with exponential backoff, offline swipe outbox, iPad layouts, keyboard shortcuts, VoiceOver actions
- Unit tests (Swift Testing) for services and stores

Not done:
- **gRPC adapters.** `RumbleProto` has the sketch protos and plugin setup but nothing implements `DeckService` etc. on top of it yet. The app runs on the fakes.
- Auth interceptor (token as metadata, refresh on `unauthenticated`), keepalive, per-call deadlines (2 s swipes, 5 s recipes/plans)
- Live Activity (needs a Widget Extension target with `ActivityKit` attributes; `NSSupportsLiveActivities` is already set)
- Persist the swipe queue, recipe cache and shopping list in SwiftData (only the pantry is persisted)
- Image cache (URLSession + disk), "record as cooked" / taste profile, bidirectional pantry sync
- App icon, real bundle identifier and signing team
- UI tests for the two core flows

## On the Mac

```sh
brew install xcodegen protobuf
# 1. Check the packages build and the tests pass
for p in RumbleServices RumbleState; do (cd Packages/$p && swift test); done
# 2. Check the proto package resolves and generates (verifies package versions and the plugin config)
(cd Packages/RumbleProto && swift build)
# 3. Generate and open the app
xcodegen generate && open Rumble.xcodeproj
```

Things to double-check against current releases: the grpc-swift-2 / grpc-swift-protobuf / nio-transport version ranges and product names in `RumbleProto/Package.swift`, the `visibility` key in `grpc-swift-proto-generator-config.json`, and the `@ModelActor` init visibility in `SwiftDataPantry.swift`.

## Open questions

See the checklist at the end of the design doc (proto repo and versioning, plain gRPC vs Connect, auth, streamed vs paged deck, craving profile, image hosting, household pantry, error handling).
