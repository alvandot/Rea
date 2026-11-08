# Rea

An iOS manga/comic reader built around a small, testable core (`ReaCore`) and a
SwiftUI app shell. Targets iOS 16+, written to be built on a Mac with Xcode —
there is no vendored Swift toolchain in this repo.

```
Rea/
├── Package.swift                 # ReaCore (library) + ReaCoreTests
├── project.yml                   # XcodeGen spec for the app target
├── Sources/ReaCore/
│   ├── Models/                   # Series, Chapter, ReadingProgress, StableID
│   ├── Source/                   # ContentSource protocol, MangaDex, local files
│   ├── Reader/                   # CBZ/ZIP, PDF, image folder, settings
│   ├── Storage/                  # JSON + Core Data/CloudKit library stores
│   ├── Download/                 # chapter page cache with AsyncStream progress
│   ├── Translation/              # OCR + translator protocols, HTTP provider
│   ├── Tracking/                 # MAL + AniList list sync
│   ├── OAuth/                    # PKCE, callback parsing, token exchange
│   ├── Extensions/               # JavaScriptCore source runtime
│   └── Library/                  # filtering
├── App/Rea/
│   ├── Core/                     # AppModel, OCR, translation, OAuth coordinator
│   ├── Features/                 # SwiftUI screens
│   └── Resources/
│       ├── Assets.xcassets/      # AppIcon, AccentColor, ReaderBackground
│       └── Extensions/           # sample JS source
├── Tools/make_app_icons.py       # regenerates the icon set (stdlib only)
└── Tests/ReaCoreTests/
```

## Build

```bash
# 1. Core tests (no Xcode project needed)
swift test

# 2. Generate the Xcode project
brew install xcodegen
xcodegen generate
open Rea.xcodeproj
```

Then, in Xcode:

1. Set your **Development Team** on the `Rea` target.
2. Enable **iCloud → CloudKit** and pick/create the container
   `iCloud.app.rea.reader` (must match `Rea.entitlements`).
3. Optional: paste tracker client IDs into `App/Rea/Info.plist` under
   `ReaTracker → myanimelist|anilist → ClientID`. Without them the
   "Connect" buttons explain what's missing instead of failing silently.

Run on a simulator or device. If CloudKit is unavailable (no team, no
entitlement) `AppModel` falls back to the JSON library store automatically, so
the app still works.

## CI

Three workflows in `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-checks.yml` | every PR + push to `main` | `swift test` and an unsigned iPhone 13 Pro simulator build, in parallel; a `gate` job fails the PR unless both pass |
| `build-ipa.yml` | push to `main`, manual | archives and exports an IPA (signed if secrets are set, otherwise a zipped `.app`) |
| `testflight.yml` | manual only | `swift test` → `fastlane beta` → App Store Connect upload |

`pr-checks.yml` is the floor: nothing reaches TestFlight unless the core tests
and the SwiftUI compile both go green first.

## TestFlight (fastlane)

`fastlane/Fastfile` has four lanes:

| Lane | What it does |
|---|---|
| `fastlane test` | `swift test --parallel` + a Debug build against the **iPhone 13 Pro** simulator |
| `fastlane ipa` | development-signed IPA into `build/Rea.ipa` |
| `fastlane beta` | Release archive → App Store Connect export → TestFlight upload |
| `fastlane beta skip_upload:true` | same build, no upload — useful for inspecting the IPA |
| `fastlane upload ipa:path.ipa` | upload an IPA you already have |

Signing uses an **App Store Connect API key**, not `match`, so no certificates
live in git.

```bash
bundle install
export REA_TEAM_ID=ABCDE12345
export REA_ASC_KEY_ID=XXXXXXXXXX
export REA_ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export REA_ASC_KEY_PATH=/secure/AuthKey_XXXXXXXXXX.p8
bundle exec fastlane beta
```

Certificates still have to be on the machine running fastlane (Xcode's own
automatic signing manages that locally). On CI, `.github/workflows/testflight.yml`
does it end to end — manual dispatch only, so shipping is a decision:

| Secret | Content |
|---|---|
| `REA_TEAM_ID` | 10-char team ID |
| `REA_ASC_KEY_ID` | API key ID |
| `REA_ASC_ISSUER_ID` | API issuer ID |
| `REA_ASC_KEY_BASE64` | `base64 < AuthKey_XXXX.p8` |
| `REA_CERT_P12_BASE64` | `base64 < dist.p12` |
| `REA_CERT_PASSWORD` | password for `dist.p12` |
| `REA_PROVISIONING_PROFILE_BASE64` | `base64 < rea-appstore.mobileprovision` |
| `REA_KEYCHAIN_PASSWORD` | optional, random if unset |

The workflow imports the identity into a throwaway keychain, runs `swift test`,
then `bundle exec fastlane beta`, uploads the IPA as an artifact, and deletes
the keychain. Export options live in `Config/ExportOptions.AppStore.plist`
(`method: app-store-connect`, `uploadSymbols: true`).

Build numbers default to UTC `YYYYMMDDHHMM`; set `REA_BUILD_NUMBER` to pin one.
TestFlight notes come from `REA_CHANGELOG` (or the workflow's `changelog` input).
External distribution is off — builds land in internal testing and you promote
them from App Store Connect.

## Building an IPA for iPhone 13 Pro

This repo cannot produce an IPA on Linux/WSL — that needs Xcode, `codesign`,
and Apple's signing. `.github/workflows/build-ipa.yml` does it on a macOS
runner instead.

**Unsigned path (no secrets).** Push to `main` or run *Build IPA* manually.
You get `Rea-unsigned-<run>.zip` — the `.app` bundle. It runs in the simulator
but will not install on a physical iPhone 13 Pro until re-signed.

**Signed path.** Add these repository secrets:

| Secret | What it is |
|---|---|
| `REA_TEAM_ID` | 10-char Apple Developer team ID |
| `REA_CERT_P12_BASE64` | `base64 -i dev.p12 \| pbcopy` of your signing cert |
| `REA_CERT_PASSWORD` | password used when exporting the `.p12` |
| `REA_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision \| pbcopy` |
| `REA_KEYCHAIN_PASSWORD` | optional; random string for the temp keychain |

The workflow then imports the identity, injects `DEVELOPMENT_TEAM` into
`project.yml`, archives for `generic/platform=iOS`, and exports `Rea.ipa` with
`Config/ExportOptions.plist` (`method: development`). The IPA is a run
artifact, retained 14 days.

iPhone 13 Pro specifically: the archive is device-generic, so the same IPA
covers every arm64 iPhone. The 13 Pro is only pinned as the *simulator* used
for the `swift test`/smoke stage — no device UDID or `xcodebuild -destination
id=` is required unless you want to install straight to a tethered phone, in
which case add its UDID to the provisioning profile and use
`xcrun devicectl device install app --device <udid>`.

To build on your own Mac instead:

```bash
xcodegen generate
xcodebuild archive -project Rea.xcodeproj -scheme Rea \
  -destination 'generic/platform=iOS' \
  -archivePath build/Rea.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/Rea.xcarchive \
  -exportPath build/export -exportOptionsPlist Config/ExportOptions.plist
```

## Design notes

- **Stable identity.** `StableID.uuid(sourceID:remoteID:)` hashes a source +
  remote key into a deterministic UUID, so re-fetching a series never forks the
  local record.
- **Two storage backends behind one protocol.** `JSONLibraryStore` is a single
  atomic file. `CoreDataLibraryStore` builds its model programmatically (no
  `.xcdatamodeld` resource) and uses `NSPersistentCloudKitContainer`.
- **Pages on demand.** `PageResource` is either a remote URL or a local file;
  the reader prefetches a ±1/+2 window and writes the resume point after every
  page change.
- **Downloads report through `AsyncStream`.** `DownloadManager` emits one
  `DownloadRecord` per state change so the UI never polls.
- **Trackers fail independently.** `TrackingManager.syncProgress` collects
  per-tracker failures into a `SyncReport` and leaves failed links untouched so
  the next sync retries them.
- **Extensions are sandboxed to one bridge.** A `JSContext` per extension gets a
  single native function (`rea.fetch`). No file, keychain, or system access.

## Honest limitations

- **CBR/RAR is not supported.** Only ZIP-based CBZ, PDF, and image folders read
  locally. `LocalDocument.reader(for:)` throws on `.cbr`.
- **Mihon compatibility is partial.** Rea implements the same *concepts*
  (sources, chapters, page lists, extension manifests) but not Mihon's Kotlin
  extension ABI. Existing Mihon `.apk` extensions will not load. The JS runtime
  here is its own, documented contract (`rea.source.*`).
- **On-device translation needs iOS 17+.** Apple's Translation framework is
  gated behind `.translationTask`, which the current adapter expects the UI to
  supply. On iOS 16 the on-device provider reports unavailability; use the
  remote provider instead.
- **OCR needs Vision + ImageIO** (both present on iOS). The test target does not
  exercise OCR.
- **No thumbnails cache yet.** Covers load through `AsyncImage`.

## App icon

`App/Rea/Resources/Assets.xcassets/AppIcon.appiconset` is a complete universal
icon set (iPhone, iPad, marketing 1024). All PNGs are generated from a single
1024px master by `Tools/make_app_icons.py`, which uses only the Python standard
library — no Pillow, no ImageMagick:

```bash
python3 Tools/make_app_icons.py   # rewrites every size in the catalog
```

Edit the colours in `draw_master()` (`ground_top`, `accent`, `highlight`) and
rerun to restyle; the `Contents.json` slot map is fixed and already matches.
`AccentColor` and `ReaderBackground` are story-agnostic colour sets the app
picks up automatically.

## Testing

`Tests/ReaCoreTests` covers ZIP parsing (built in memory, no fixtures), the JSON
library store including flag preservation across chapter refresh, library
filtering, the local source, the download manager, translation (including a
stubbed HTTP transport), tracker sync, and OAuth (PKCE, callback parsing, token
exchange formatting).
# Rea
