# Memory Trails — Mac App Store Submission

The Xcode project now contains two separate macOS targets:

- **Memory Trails** — full direct-download edition with Accessibility-based detailed capture.
- **Memory Trails App Store** — sandboxed edition intended for Mac App Store submission.

## What the App Store edition keeps

- Application-switch history using standard macOS workspace activation notifications.
- Optional clipboard-text history. It is OFF by default until the user enables it.
- Manual memories.
- Today / Timeline.
- Insights from locally captured activity.
- Ask Memory Trails over app-switch, clipboard, and manual-memory history.
- Favorites.
- 30-day local retention.
- JSON export using a standard macOS Save panel.
- Local bundle-ID exclusions.

## What it intentionally does not include

The App Store edition does not use Accessibility / AXUIElement to inspect other applications. It therefore does not capture:

- Detailed Outlook subject/sender information.
- Teams conversation titles.
- Browser-tab/page titles from other apps.
- Other applications' focused-window content.

Use the full direct-download target for those features.

## Prepare Xcode

1. Open **Memory Trails.xcodeproj**.
2. In the scheme selector choose **Memory Trails App Store**.
3. Select the **Memory Trails App Store** target.
4. Open **Signing & Capabilities**.
5. Select your Apple Developer Team.
6. Confirm the bundle identifier is **com.ram1424.memorytrail**.\n   - The bundle identifier remains intentionally unchanged for signing and App Store continuity; the customer-facing app name is **Memory Trails**.
7. Confirm **App Sandbox** is enabled.
8. Confirm **User Selected File → Read/Write** is enabled.

The target already includes:

- `MemoryTrail/AppStore/MemoryTrailAppStore.entitlements`
- `MemoryTrail/AppStore/PrivacyInfo.xcprivacy`
- the `APP_STORE_EDITION` Swift compilation condition
- a separate sandbox-safe capture coordinator
- App Store-specific onboarding and Settings
- a shared **Memory Trails App Store** Xcode scheme

## Create the App Store Connect record

Before your first upload:

1. Go to App Store Connect.
2. Choose **Apps → + → New App**.
3. Platform: **macOS**.
4. Name: **Memory Trails**.
5. Bundle ID: **com.ram1424.memorytrail**.
6. SKU: for example `MEMORYTRAIL-MAC-001`.
7. Primary category: **Productivity**.

## Archive and upload

1. In Xcode select **Memory Trails App Store**.
2. Choose a generic macOS archive destination / Any Mac.
3. Choose **Product → Archive**.
4. In Organizer select the new archive.
5. Click **Distribute App**.
6. Choose **App Store Connect**.
7. Choose **Upload**.
8. Allow Xcode to validate the archive and upload it.

The App Store edition intentionally has no GitHub self-updater. App Store updates must be delivered by the Mac App Store.

## Recommended App Review notes

Memory Trails is a privacy-first local activity-history application.

The Mac App Store edition is sandboxed and does not request Accessibility access. It records foreground application activation events using standard NSWorkspace notifications. Users may optionally enable clipboard text capture; clipboard capture is off by default. Captured history is stored locally in the app container and is not uploaded to Memory Trails servers.

Testing steps:

1. Launch Memory Trails and complete onboarding.
2. Switch between several applications.
3. Return to Memory Trails → Today and confirm the application switches appear.
4. Optionally enable Clipboard Capture in Settings, copy text in another application, then return to Memory Trails to confirm the local clipboard item appears.
5. Open Insights and Ask Memory Trails to review/search the local history.
6. Use Settings → Export Activity as JSON and choose a save location.

## App Privacy

The included privacy manifest declares no tracking and no transmitted collected-data types. It also declares the app's own UserDefaults use with approved reason `CA92.1`.

In App Store Connect, answer App Privacy questions based on the submitted App Store binary and Apple's current definition of data collection.

## Important

Archive **Memory Trails App Store**, not the direct-download **Memory Trails** target.
