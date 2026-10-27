# Memory Lane

**Memory Lane** is a private, local-first activity timeline for macOS. It helps you retrace your digital day by remembering the apps, focused windows, pages, conversations, links, notes, and copied text that make up your workflow.

Instead of asking, _“Where did I see that?”_ or _“What was I doing before that meeting?”_, open Memory Lane and search what you remember.

## What it does

- Builds a chronological timeline of app activity.
- Watches meaningful focused-window title changes through macOS Accessibility APIs.
- Captures supported context from Safari, Mail, Outlook, Teams, Chrome, and other apps when that metadata is exposed by macOS.
- Searches across captured memories.
- Lets you favorite important moments and create manual memories.
- Stores available source links for quick return to prior work.
- Provides menu-bar Pause/Resume controls.
- Supports clipboard-text capture, enabled by default and configurable in Settings.
- Supports per-app exclusions, with Wallet and Passwords always excluded.

## Privacy

Memory Lane is designed to be local-first.

- Timeline data is stored locally using SwiftData.
- No account system is required.
- No advertising SDK is included.
- No analytics SDK is included.
- Capture can be paused at any time.
- Clipboard capture can be disabled.
- App exclusions let you control what Memory Lane intentionally remembers.

## Requirements

- macOS 14+
- Xcode 16+ for development
- Accessibility permission for granular focused-window context

## Download

The latest DMG is available from the GitHub release:

https://github.com/ram1424/Memory-Lane/releases/tag/v1.0.0

## Website

The product site is published from the `docs/` directory through GitHub Pages at:

https://ram1424.github.io/Memory-Lane/

## Development

Open `Memory Lane.xcodeproj` in Xcode and select the **Memory Lane** scheme.

Bundle identifier:

`com.ram1424.memorylane`
