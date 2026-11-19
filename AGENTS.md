# Yattee Development Guide for AI Agents

## Deployment Targets

**iOS:** 18.0+ | **macOS:** 15.0+ | **tvOS:** 18.0+

This project targets the latest OS versions only - use newest APIs freely without availability checks.

## Build & Test Commands

**Build:** `xcodebuild -scheme Yattee -configuration Debug`  
**Test (all):** `xcodebuild test -scheme Yattee -destination 'platform=macOS'`  
**Test (single):** `xcodebuild test -scheme Yattee -destination 'platform=macOS' -only-testing:YatteeTests/TestSuiteName/testMethodName`  
**Lint:** `periphery scan` (config: `.periphery.yml`)

## Build Configurations

Three configurations exist, mapped to distribution channels:

| Configuration | Sparkle (`#if SPARKLE`) | Used for |
|---|---|---|
| `Debug` | off | local development, tests |
| `Release` | off | App Store / TestFlight (`fastlane mac beta`) — must stay Sparkle-free, App Review rejects auto-update frameworks |
| `Release-DeveloperID` | **on** | Developer ID notarized build (`fastlane mac build_and_notarize`), distributed via GitHub Releases + Homebrew cask, receives Sparkle updates |

All Sparkle-dependent code must be wrapped in `#if SPARKLE ... #endif` so the `Release` variant links zero Sparkle symbols. When adding new Sparkle features, test both configs build clean on macOS.

## Code Style

**Language:** Swift 5.0+ with strict concurrency (Swift 6 mode enabled)  
**UI:** SwiftUI with `@Observable` macro for view models (not `ObservableObject`)  
**Concurrency:** Use `actor` for services, `@MainActor` for UI-related code, `async/await` everywhere  
**Testing:** Swift Testing framework (`@Test`, `@Suite`, `#expect`) - NOT XCTest

## Imports & Organization

**Import order:** Foundation first, then SwiftUI, then @testable imports  
**File headers:** Include `//  FileName.swift`, `//  Yattee`, and brief comment describing purpose  
**MARK comments:** Use `// MARK: - Section Name` to organize code sections  
**Sendable:** All models, errors, and actors must conform to `Sendable`

## Types & Naming

**Models:** Immutable structs with `Codable, Hashable, Sendable` conformance  
**Services:** Use `actor` for thread-safe services, `final class` for `@Observable` view models  
**Enums:** Use associated values for typed errors (see `APIError.swift`)  
**Optionals:** Prefer guard-let unwrapping; use `if let` for simple cases  
**Naming:** camelCase for variables/functions, PascalCase for types, clear descriptive names

## Error Handling

**Errors:** Define typed enum errors conforming to `Error, LocalizedError, Equatable, Sendable`  
**Async throws:** All async network/IO operations should throw typed errors  
**Logging:** Use `LoggingService.shared` for all logging (see `HTTPClient.swift` for patterns)  
**User feedback:** Provide localized error descriptions via `errorDescription`

## Testing & Debugging

**Add logging/visual clues** (borders, backgrounds) when debugging issues - then ask user for results  
**If first fix doesn't work:** Add debug code before second attempt to understand the issue better

## UI Testing (Ruby/RSpec with AXe CLI)

**Run UI tests:** `./bin/ui-test --skip-build --keep-simulator`  
**Run single spec:** `SKIP_BUILD=1 KEEP_SIMULATOR=1 bundle exec rspec spec/ui/smoke/search_spec.rb`

**Accessibility labels vs identifiers:** On iOS 26+, `.accessibilityIdentifier()` doesn't work reliably on `Group`, `ScrollView`, and some container views (AXUniqueId comes back empty). Use `.accessibilityLabel()` instead, which maps to `AXLabel` and can be detected via AXe's `text_visible?()` method.

**iOS 26 TabView search:** The search field is integrated into the bottom tab bar with `Tab(role: .search)`. Typing `\n` doesn't submit - use hardware key press via `press_return` (AXe key 40).

**ScrollView children:** Video rows inside `LazyVStack`/`ScrollView` aren't exposed in the accessibility tree. Use coordinate-based tapping instead.

## Yattee Y (this fork: yuwei-liang/yattee, branch `yuwei`)

Personal fork built for one person's iPhone/iPad/Mac. Keep changes small and in their own files so upstream merges stay easy; merge `upstream/main` into `yuwei` periodically.

**Identity:** bundle `com.yuweiliang.yattee` (+ `.ShareExtension`, `.TopShelf`), app group `group.com.yuweiliang.yattee.shared`, iCloud container `iCloud.com.yuweiliang.yattee`, team `234Y5MB95R`, display name "Yattee Y". Never put the upstream IDs back.

**Builds need Xcode 27** (upstream uses iOS 27 SDK APIs); the owner's Mac has Xcode 26, so build, test and ship on GitHub Actions (`runs-on: xcode-27`, free for this public repo):
- `.github/workflows/yattee-y-testflight.yml` — every push to `yuwei` archives iOS and uploads to TestFlight (internal group "Me", automatic distribution). Add `[skip ci]` to commit messages that don't need a build.
- `.github/workflows/yattee-y-dev-ipa.yml` — manual; development-signed IPA with `YATTEE_DEV_LOG` (mpv log + font report to `Documents/dev.log`) for registered test devices. Install: `xcrun devicectl device install app --device <id> <ipa>`; read logs: `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.yuweiliang.yattee --source Documents/dev.log --destination .`
- `.github/workflows/yattee-y-tests.yml` — `xcodebuild test` in the iOS Simulator (unsigned macOS hosts crash), on every push.
**Cost must stay $0:** the repo stays public and workflows use only the standard `xcode-27` runner (free for public repos). Never add larger/paid runners, matrix fan-outs or long artifact retention; mark commits that need no build `[skip ci]`.
**Release rhythm:** new features go to the iPhone XR first (dev IPA via `devicectl`); push without `[skip ci]` only once Yuwei has tried them there, so TestFlight (the main phone) only gets tried builds. TestFlight builds expire after 90 days.
Signing is Xcode automatic signing with an App Store Connect API key in repo secrets (`ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) plus one fixed Apple Development certificate (`DEV_CERT_P12`, `DEV_CERT_PASSWORD`) imported into a throwaway keychain each run. Without it, every fresh runner minted a new development certificate and hit Apple's cap (11 revoked on 2026-11-18). No certificates in the repo. Never print or commit the key.

**CloudKit schema:** `cloudkit/schema.ckdb` mirrors `CloudKitRecordMapper`. TestFlight builds use the Production environment, which does not create fields on the fly: when you add a record type or field, update the file, import it into Development in the CloudKit Console, then "Deploy Schema Changes" to Production — before shipping the build that writes it.

**Fork features:**
- `Yattee/Core/SourceLink.swift` — `yattee://add-source?url=&name=&proxy=1&user=&pass=` adds/updates a Yattee Server source and stores the login in the Keychain. Handled at the top of `onOpenURL`, before any logging. Deliver it to a device with `devicectl ... --payload-url`, never through chats or notes.
- CJK subtitles: iOS system CJK fonts live outside the sandbox (`/var/mobile/Library/UserFonts`), so libass cannot open them and draws boxes. We bundle Noto Sans SC (`Yattee/Resources/SubtitleFonts`, SIL OFL), copy it to Application Support at runtime and set `sub-fonts-dir`; `SubtitleFont` maps to it (`Services/Player/MPV/SubtitleFonts.swift`).
- Home = recommendation feed when a Yattee Server is enabled (`HomeView.yatteeYHomeContent`, `RecommendedFeedSection.swift`, `HomeChipsRow.swift`): Claude's picks from `/api/v1/popular` with the reason (`description`), feedback via `POST /api/v1/recommended/feedback` (more/deeper/less/channel; "less" waits a 6 s undo window), "换一批" via `POST /api/v1/recommended/rebuild` (`YatteeServerAPI+Recommendations.swift`). tvOS and setups without a Yattee Server keep the upstream home.
- unspin: "用 unspin 分析" in the shared video context menu and the feed card ⋯ menu queues the video on our server (`POST /api/v1/unspin`, `YatteeServerAPI+Unspin.swift`); a worker on the owner's Mac (`youtube-theft/deploy/unspin-worker.py`, LaunchAgent) runs the unspin Claude Code skill and posts the report back; `UnspinReportsView` (home chip "unspin") lists the queue and reports.
- Sleep timer (`Services/Player/SleepTimer.swift`, iOS/macOS): "睡眠定时" submenu in the player-context video menu, moon badge in `PlayerControlsView` and `MiniPlayerView`, end-of-video hook in `PlayerService.backendDidFinishPlaying`. Adapted from 7inh/yattee 5fd6c3d.
- Early end-of-file refresh (max 2 per video) in `backendDidFinishPlaying` and un-finishing below 90% in `WatchEntry.updateProgress`; adapted from michaelhalstead/yattee 9a062a5.
- Tests for fork code live in `YatteeTests/YatteeYTests.swift`.
