# Memory Trail

<p align="center">
  <img src="Branding/MemoryTrailIconMaster.png" width="168" alt="Memory Trail app icon">
</p>

<p align="center"><strong>Your workday, remembered locally.</strong></p>

Memory Trail is a privacy-first macOS activity timeline that helps you retrace what you were doing across browsers, email, chat, files, documents, and the clipboard.

It captures useful context exposed by supported apps, stores it locally on your Mac, and presents it as a searchable chronological history. Memory Trail does not send your activity to an external service and does not generate AI summaries of your timeline.

## Download

**Latest release: Memory Trail 1.0.1**

[Download Memory Trail 1.0.1 for macOS](https://github.com/ram1424/Memory-Lane/releases/download/v1.0.1/MemoryTrail-1.0.1.dmg)

Requires macOS 14 or later. Detailed activity capture requires macOS Accessibility permission.

## Screenshots

### Today
![Memory Trail Today view](docs/screenshots/today-ui.png)

### Ask Memory Trail
![Ask Memory Trail](docs/screenshots/ask-memory-trail-ui.png)

### Favorites
![Memory Trail Favorites](docs/screenshots/favorites-ui.png)

_All screenshots use generic demo data._

## Core Features

- **Live activity timeline** with the newest activity first
- **Ask Memory Trail** search across your local history
- **Browser context** including page and tab titles when available
- **Outlook and Mail context** including subject-level activity
- **Teams conversation context** including participant names when exposed through Accessibility
- **Files and documents** from Finder, Word, Excel, PowerPoint, Preview, OneNote, and supported apps
- **Clipboard history** for supported text, links, and code snippets
- **Favorites and manual memories**
- **App exclusions and pause controls**
- **Menu bar operation**
- **Local-only storage** using SwiftData

## Privacy

Memory Trail is designed to keep your activity on your computer.

- No Memory Trail account
- No analytics SDK
- No advertising SDK
- No cloud timeline storage
- No external connectors
- Apps can be excluded from capture
- Passwords and Wallet are excluded by default
- Clipboard capture can be disabled
- Source code is available in this repository for review

Memory Trail is intended as a personal productivity and activity-retracing tool. It is not designed as employee monitoring software, a keylogger, or a screen recorder.

## Accessibility Permission

For detailed window and app context, enable Memory Trail under:

**System Settings → Privacy & Security → Accessibility**

If Memory Trail does not appear automatically, use the **+** button to add **Memory Trail.app**, enable it, and relaunch the app.

## Build From Source

1. Clone this repository.
2. Open **Memory Trail.xcodeproj** in Xcode.
3. Select the **Memory Trail** scheme.
4. Build and run the macOS target.
5. Grant Accessibility permission when prompted.

**Bundle identifier:** `com.ram1424.memorytrail`

## Current Release

**Version 1.0.1** is the active macOS release.
