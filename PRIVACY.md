# Memory Trails Privacy Policy

**Effective date:** November 3, 2026  
**Last updated:** November 5, 2026  
**Applies to:** Memory Trails for Windows and macOS

Memory Trails is a privacy-first, locally run productivity application designed to help you retrace recent computer activity without creating a cloud copy of your captured history.

## 1. Privacy by design

Memory Trails processes and stores captured activity locally on your computer.

Memory Trails does **not** operate a cloud timeline service, does not require a Memory Trails account, and does not transmit your captured activity history to Memory Trails servers.

Memory Trails does not sell captured activity data and does not use captured activity for advertising, behavioral profiling, or AI model training.

## 2. Information Memory Trails may process locally

Depending on your operating system, enabled features, permissions, applications, and the information exposed locally by those applications, Memory Trails may process and store:

- Application names and process or bundle identifiers.
- Focused window, page, tab, document, notebook, email, or conversation titles.
- Browser URLs when exposed by a supported browser.
- File, folder, and document names or local paths when available.
- Clipboard text, links, or code when clipboard capture is enabled.
- Manual memories, notes, Favorites, and other information you intentionally add.
- Local timestamps, categories, preferences, exclusions, onboarding state, and similar app settings.

Memory Trails is intended to capture useful activity context, not the complete contents of every application you use.

Memory Trails does **not intentionally capture passwords or credentials**. Sensitive applications can be excluded from capture, and common credential-related applications may be excluded by default.

## 3. Platform permissions and local activity capture

### Windows

Memory Trails may use standard Windows desktop APIs and Windows UI Automation to identify the foreground application and obtain locally visible window context. This can include window titles, browser titles, email subject lines, conversation titles, document names, and related metadata exposed by Windows or supported applications.

The Microsoft Store build is a packaged classic desktop application and may use the `runFullTrust` capability so it can operate as a normal WPF desktop application at the user's standard privilege level. Memory Trails does not use this capability to request administrator elevation, install drivers or services, or bypass Windows security controls.

### macOS — direct-download edition

The direct-download macOS edition may use Accessibility APIs, after the user grants macOS Accessibility permission, to read locally exposed focused-window context such as supported browser page titles, Outlook subjects and senders, Teams conversation titles, and document names.

### macOS — Mac App Store edition

The Mac App Store edition runs inside Apple’s App Sandbox and does **not** use Accessibility / AXUIElement to inspect other applications.

The App Store edition may process locally:

- Foreground application activation events published by macOS, including the application name and bundle identifier.
- Clipboard text only when the user explicitly enables Clipboard Capture. Clipboard Capture is off by default for this edition.
- Manual memories, Favorites, searches, local timestamps, preferences, and exclusions.

The Mac App Store edition does not capture detailed Outlook subjects or senders, Teams conversation titles, browser-tab titles, or other focused-window content from other applications.

## 4. Clipboard capture

Clipboard capture is optional and can be disabled.

When enabled, supported copied text, links, or code may be stored in your local Memory Trails history.

Memory Trails does not upload clipboard history to a Memory Trails server.

## 5. Excluded applications and capture controls

Memory Trails provides controls that may include:

- Pause all capture.
- Enable or disable app/window activity capture.
- Enable or disable clipboard capture.
- Exclude applications or processes from capture.
- Clear the last 7 days, the last 30 days, or all activity history.
- Export your locally stored activity history to a JSON file you choose.
- Clear temporary app cache or reset preferences without deleting saved history where indicated.

Users should configure exclusions for applications containing information they do not want represented in their local timeline.

## 6. Where captured data is stored

Captured activity is stored locally on the device running Memory Trails.

On Windows, local data is stored within the user's Windows profile and local application-data locations.

On macOS, captured activity is stored in a clearly named local SwiftData store at `~/Library/Application Support/Memory Trails/MemoryTrails.store` (or the corresponding app-container Application Support path when macOS sandboxing applies).

Memory Trails does not provide cloud synchronization for the captured timeline.

## 7. Network connections and software updates

Memory Trails does not send captured timeline entries, clipboard contents, window titles, document paths, conversation titles, Favorites, searches, or manually added memories as part of an update check.

### Microsoft Store version

The Microsoft Store version relies on Microsoft Store and Windows for application distribution and updates. Memory Trails’ GitHub self-updater is disabled in the Microsoft Store build.

Microsoft may process ordinary Store and device information according to Microsoft's own privacy terms.

### Mac App Store version

The Mac App Store edition relies on the Mac App Store for application distribution and updates. Memory Trails’ GitHub self-updater is not included in this build.

Apple may process ordinary App Store and device information according to Apple's own privacy terms.

### Direct-download versions

Direct-download builds may contact public GitHub resources to:

- Check whether a newer Memory Trails release is available.
- Download an application update you choose to install.
- Open the public source repository, releases, documentation, or privacy policy.

These requests may expose ordinary network information to GitHub, such as IP address, user agent, and request timestamp. GitHub handles that information under its own privacy practices.

This update connectivity does **not** include your captured activity history.

## 8. Analytics, advertising, profiling, and AI

Memory Trails does not include third-party advertising SDKs or behavioral advertising.

Memory Trails does not use your captured activity to create advertising profiles.

Memory Trails does not send captured activity to external AI providers for model training, fine-tuning, remote summarization, profiling, or inference.

Memory Trails does not scrape your captured activity for AI datasets.

## 9. Sharing and sale of captured activity

Memory Trails does not sell your captured activity history.

Memory Trails does not transmit captured activity to advertisers or data brokers.

Because Memory Trails stores information locally, anyone or any software with sufficient access to your operating-system account or local files may potentially access Memory Trails data.

You are responsible for securing your device using appropriate account security, passwords, encryption, operating-system updates, and other device-security controls.

## 10. Data retention and deletion

Memory Trails retains locally stored captured history for **30 days by default**. Activity older than 30 days is automatically removed from the local Memory Trails store. You can also delete the last 7 days, the last 30 days, or all local history at any time from Settings.

Deleting the application itself may not automatically delete every preference, cache, database, or application-support file maintained by the operating system.

The **Clear App Cache** function is intended to reset temporary state and preferences and is not intended to delete saved timeline history unless the app specifically states otherwise.

## 11. Children's privacy

Memory Trails is a general-purpose productivity application and is not designed specifically for children.

Memory Trails does not operate a remote account service that knowingly creates cloud profiles of children based on captured activity.

## 12. Security

Memory Trails reduces privacy exposure by keeping captured activity local and avoiding a cloud timeline service.

No software or local storage system can guarantee absolute security. Users should keep their operating system updated, protect their account, use device encryption where appropriate, and configure exclusions for sensitive applications.

## 13. Third-party applications and services

Memory Trails reads information made locally available by the operating system and supported applications.

Memory Trails does not control the privacy practices of Microsoft Windows, macOS, GitHub, Microsoft Store, Microsoft Outlook, Microsoft Teams, web browsers, or other third-party products and services.

Those products may independently collect or process information under their own privacy policies.

## 14. Source-code transparency

Memory Trails’ source code is publicly available for review so users and security researchers can inspect how capture, storage, privacy controls, and update behavior are implemented.

Source repository:

https://github.com/ram1424/Memory-Trail

## 15. Changes to this policy

This Privacy Policy may be updated when Memory Trails’ functionality, permissions, storage model, distribution method, or network behavior changes.

Material privacy-related changes will be reflected in the public repository and, when appropriate, in the application changelog or release notes.

## 16. Contact and questions

Questions, privacy concerns, or reports about Memory Trails can be submitted through the Memory Trails GitHub repository:

https://github.com/ram1424/Memory-Trail/issues

Do not include passwords, credentials, private timeline content, clipboard contents, or other sensitive personal information in a public GitHub issue.

---

## Plain-language summary

Memory Trails is built around a simple principle: **your captured activity belongs on your computer.**

- **Local-first:** captured activity is processed and stored locally.
- **No Memory Trails cloud timeline:** captured history is not uploaded to Memory Trails servers.
- **No Memory Trails account required:** there is no remote profile required for capture.
- **No sale of captured activity:** Memory Trails does not sell captured activity data.
- **No advertising or AI training:** captured activity is not used for behavioral advertising or external AI model training.
- **Store-managed updates on Windows Store builds:** the Microsoft Store version relies on Microsoft Store for updates.
- **Limited GitHub connectivity on direct builds:** direct-download builds may use GitHub for public release checks, downloads, source code, and documentation; captured activity is not included in those requests.
