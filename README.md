# Recall

Recall is a privacy-first personal activity timeline for macOS and iOS. This repository contains a native SwiftUI MVP.

## Included in this MVP

- Local SwiftData timeline
- Full-text/token search across captured memories
- Favorites
- Manual memory capture
- URL/context fields
- macOS menu-bar Pause/Resume control
- Optional macOS app-switch capture
- Optional macOS clipboard-text capture
- Per-bundle-ID exclusion list with password-manager defaults
- Shared SwiftUI UI for macOS and iOS

## Platform behavior

### macOS
Recall can automatically remember when you switch into an application. Clipboard capture is available but OFF by default. Both features can be paused globally and excluded by bundle ID.

### iOS
Apple's sandbox does not allow an app to continuously inspect what happens in other apps. This build automatically logs Recall app sessions so the iOS timeline and local data store can be verified, and it supports manual capture. Settings also includes a Create Test Capture button for Simulator/device validation. A Share Extension is the logical next addition for sending URLs/text/files into Recall from Safari and other apps.

## Requirements

- Xcode 16 or newer
- iOS 17+
- macOS 14+
- Swift 5.9+

## Open

Open `Recall.xcodeproj` in Xcode.

The project contains two targets:

- `Recall iOS`
- `Recall macOS`

Select your signing team before running on a physical device.

## Privacy model

No network code, analytics SDK, account system, or cloud service is included. Data is stored locally in SwiftData. Clipboard capture is disabled by default.

## Recommended next milestones

1. iOS/macOS Share Extension for links, text and files.
2. Browser extension for richer URL/page-title capture.
3. File-open capture on macOS using explicit user-granted folders.
4. On-device embeddings for semantic search.
5. Encrypted CloudKit/iCloud sync.
6. “What was I doing?” session summaries and Resume Work bundles.
7. Retention controls (7 days / 30 days / forever) and export/delete tools.

## Important implementation note

This environment is Linux and cannot run Xcode, so the project has been generated and structurally checked here but cannot be compiled against Apple SDKs in this environment. Xcode will perform the final Apple-platform compilation/signing validation.
