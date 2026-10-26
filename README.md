# Recall

Recall is a privacy-first personal activity timeline for macOS. This repository contains a native SwiftUI macOS app.

## Included

- Local SwiftData timeline
- Full-text/token search across captured memories
- Favorites
- Manual memory capture
- URL/context fields with Open Source / Open App actions
- Menu-bar Pause/Resume control
- Automatic app-switch capture
- Focused-window title capture through macOS Accessibility
- Optional clipboard-text capture
- Per-bundle-ID exclusion list with privacy-focused defaults
- Granular Safari, Mail, Outlook, Teams, Chrome, and other window activity where apps expose Accessibility metadata

## Requirements

- Xcode 16 or newer
- macOS 14+
- Swift 5.9+

## Open

Open `Recall.xcodeproj` in Xcode and select the `Recall macOS` scheme.

Recall is a macOS-only project with a single application target.

## Permissions

For granular window activity, enable Recall under:

System Settings → Privacy & Security → Accessibility

Recall can request this permission from Settings using **Enable Accessibility Access**.

## Privacy model

No network code, analytics SDK, account system, or cloud service is included. Data is stored locally in SwiftData. Clipboard capture is disabled by default. Wallet and Passwords remain excluded from capture.

## Recommended next milestones

1. App-specific metadata adapters for Mail, Outlook, Teams, and browsers.
2. File-open capture using explicit user-granted folders.
3. On-device embeddings for semantic search.
4. Encrypted iCloud sync.
5. “What was I doing?” session summaries and Resume Work bundles.
6. Retention controls and export/delete tools.
