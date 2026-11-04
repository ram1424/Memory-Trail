# Memory Trail Privacy Policy

**Effective date:** November 3, 2026  
**Last updated:** November 3, 2026  
**Applies to:** Memory Trail for Windows and macOS

Memory Trail is a privacy-first, locally run productivity application designed to help you retrace recent computer activity without creating a cloud copy of your captured history.

## 1. Privacy by design

Memory Trail processes and stores captured activity locally on your computer.

Memory Trail does **not** operate a cloud timeline service, does not require a Memory Trail account, and does not transmit your captured activity history to Memory Trail servers.

Memory Trail does not sell captured activity data and does not use captured activity for advertising, behavioral profiling, or AI model training.

## 2. Information Memory Trail may process locally

Depending on your operating system, enabled features, permissions, applications, and the information exposed locally by those applications, Memory Trail may process and store:

- Application names and process or bundle identifiers.
- Focused window, page, tab, document, notebook, email, or conversation titles.
- Browser URLs when exposed by a supported browser.
- File, folder, and document names or local paths when available.
- Clipboard text, links, or code when clipboard capture is enabled.
- Manual memories, notes, Favorites, and other information you intentionally add.
- Local timestamps, categories, preferences, exclusions, onboarding state, and similar app settings.

Memory Trail is intended to capture useful activity context, not the complete contents of every application you use.

Memory Trail does **not intentionally capture passwords or credentials**. Sensitive applications can be excluded from capture, and common credential-related applications may be excluded by default.

## 3. Platform permissions and local activity capture

### Windows

Memory Trail may use standard Windows desktop APIs and Windows UI Automation to identify the foreground application and obtain locally visible window context. This can include window titles, browser titles, email subject lines, conversation titles, document names, and related metadata exposed by Windows or supported applications.

The Microsoft Store build is a packaged classic desktop application and may use the `runFullTrust` capability so it can operate as a normal WPF desktop application at the user's standard privilege level. Memory Trail does not use this capability to request administrator elevation, install drivers or services, or bypass Windows security controls.

## 4. Clipboard capture

Clipboard capture is optional and can be disabled.

When enabled, supported copied text, links, or code may be stored in your local Memory Trail history.

Memory Trail does not upload clipboard history to a Memory Trail server.

## 5. Excluded applications and capture controls

Memory Trail provides controls that may include:

- Pause all capture.
- Enable or disable app/window activity capture.
- Enable or disable clipboard capture.
- Exclude applications or processes from capture.
- Clear activity history.
- Clear temporary app cache or reset preferences without deleting saved history where indicated.

Users should configure exclusions for applications containing information they do not want represented in their local timeline.

## 6. Where captured data is stored

Captured activity is stored locally on the device running Memory Trail.

On Windows, local data is stored within the user's Windows profile and local application-data locations.

On macOS, local data is stored using Apple platform storage technologies and standard local preference/application-support locations.

Memory Trail does not provide cloud synchronization for the captured timeline.

## 7. Network connections and software updates

Memory Trail does not send captured timeline entries, clipboard contents, window titles, document paths, conversation titles, Favorites, searches, or manually added memories as part of an update check.

### Microsoft Store version

The Microsoft Store version relies on Microsoft Store and Windows for application distribution and updates. Memory Trail's GitHub self-updater is disabled in the Microsoft Store build.

Microsoft may process ordinary Store and device information according to Microsoft's own privacy terms.

### Direct-download versions

Direct-download builds may contact public GitHub resources to:

- Check whether a newer Memory Trail release is available.
- Download an application update you choose to install.
- Open the public source repository, releases, documentation, or privacy policy.

These requests may expose ordinary network information to GitHub, such as IP address, user agent, and request timestamp. GitHub handles that information under its own privacy practices.

This update connectivity does **not** include your captured activity history.

## 8. Analytics, advertising, profiling, and AI

Memory Trail does not include third-party advertising SDKs or behavioral advertising.

Memory Trail does not use your captured activity to create advertising profiles.

Memory Trail does not send captured activity to external AI providers for model training, fine-tuning, remote summarization, profiling, or inference.

Memory Trail does not scrape your captured activity for AI datasets.

## 9. Sharing and sale of captured activity

Memory Trail does not sell your captured activity history.

Memory Trail does not transmit captured activity to advertisers or data brokers.

Because Memory Trail stores information locally, anyone or any software with sufficient access to your operating-system account or local files may potentially access Memory Trail data.

You are responsible for securing your device using appropriate account security, passwords, encryption, operating-system updates, and other device-security controls.

## 10. Data retention and deletion

Memory Trail retains locally stored history until you delete it using available app controls, remove the app's local data, or erase the device or storage containing it.

Deleting the application itself may not automatically delete every preference, cache, database, or application-support file maintained by the operating system.

The **Clear App Cache** function is intended to reset temporary state and preferences and is not intended to delete saved timeline history unless the app specifically states otherwise.

## 11. Children's privacy

Memory Trail is a general-purpose productivity application and is not designed specifically for children.

Memory Trail does not operate a remote account service that knowingly creates cloud profiles of children based on captured activity.

## 12. Security

Memory Trail reduces privacy exposure by keeping captured activity local and avoiding a cloud timeline service.

No software or local storage system can guarantee absolute security. Users should keep their operating system updated, protect their account, use device encryption where appropriate, and configure exclusions for sensitive applications.

## 13. Third-party applications and services

Memory Trail reads information made locally available by the operating system and supported applications.

Memory Trail does not control the privacy practices of Microsoft Windows, macOS, GitHub, Microsoft Store, Microsoft Outlook, Microsoft Teams, web browsers, or other third-party products and services.

Those products may independently collect or process information under their own privacy policies.

## 14. Source-code transparency

Memory Trail's source code is publicly available for review so users and security researchers can inspect how capture, storage, privacy controls, and update behavior are implemented.

Source repository:

https://github.com/ram1424/Memory-Trail

## 15. Changes to this policy

This Privacy Policy may be updated when Memory Trail's functionality, permissions, storage model, distribution method, or network behavior changes.

Material privacy-related changes will be reflected in the public repository and, when appropriate, in the application changelog or release notes.

## 16. Contact and questions

Questions, privacy concerns, or reports about Memory Trail can be submitted through the Memory Trail GitHub repository:

https://github.com/ram1424/Memory-Trail/issues

Do not include passwords, credentials, private timeline content, clipboard contents, or other sensitive personal information in a public GitHub issue.

---

## Plain-language summary

Memory Trail is built around a simple principle: **your captured activity belongs on your computer.**

- **Local-first:** captured activity is processed and stored locally.
- **No Memory Trail cloud timeline:** captured history is not uploaded to Memory Trail servers.
- **No Memory Trail account required:** there is no remote profile required for capture.
- **No sale of captured activity:** Memory Trail does not sell captured activity data.
- **No advertising or AI training:** captured activity is not used for behavioral advertising or external AI model training.
- **Store-managed updates on Windows Store builds:** the Microsoft Store version relies on Microsoft Store for updates.
- **Limited GitHub connectivity on direct builds:** direct-download builds may use GitHub for public release checks, downloads, source code, and documentation; captured activity is not included in those requests.
