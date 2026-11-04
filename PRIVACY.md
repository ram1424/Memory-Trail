# Memory Trail Privacy Policy

**Effective date:** November 3, 2026  
**Applies to:** Memory Trail for macOS

Memory Trail is designed as a privacy-first, locally run activity-history application. Its purpose is to help you retrace what you worked on, viewed, opened, discussed, and copied on your Mac without creating a cloud copy of your activity history.

## 1. Privacy by design

Memory Trail processes and stores captured activity locally on your Mac.

**Memory Trail has no external data connectors of any kind.** It does not connect your captured activity to email accounts, cloud drives, calendars, collaboration platforms, browser-sync accounts, AI providers, analytics platforms, advertising systems, data brokers, or other external services for ingestion, enrichment, synchronization, or analysis.

**There is no Memory Trail account to create, no sign-in, no subscription account, and no remote user profile.** Memory Trail does not require credentials for a Memory Trail service because no such account service exists.

**Memory Trail does not process, transmit, upload, synchronize, back up, or store your captured activity data on any cloud service.** Captured timeline data, clipboard history, files and paths, conversation context, searches, Favorites, and manual memories remain on your Mac unless you intentionally move or copy them yourself outside the app.

**Memory Trail does not perform AI data scraping of any kind.** It does not harvest captured activity for AI datasets, send captured activity to an AI provider, use captured activity to train or fine-tune AI models, create embeddings in a cloud service, or perform remote AI summarization, profiling, or inference on your activity history.

Memory Trail does not collect, transmit, sell, share, monetize, process, or store any user data outside the user’s Mac whatsoever. All captured activity remains stored locally on the user’s Mac, is used only to provide Memory Trail’s local features, and is never sent to Memory Trail servers, cloud services, advertisers, analytics providers, AI providers, or data brokers. Put another way: Memory Trail servers can’t receive your data because, in a rather privacy-friendly plot twist, Memory Trail servers do not exist.

## 2. Information Memory Trail may process locally

Depending on the features you enable, the applications you use, and what macOS exposes to the app, Memory Trail may process and store information such as:

- Application names and bundle identifiers.
- Focused window, page, tab, document, notebook, or conversation titles.
- Browser URLs when a supported browser exposes them.
- Email subject and sender context when a supported mail application exposes it.
- Chat or conversation titles when supported applications expose them.
- File names, folder names, document names, and local file paths when available.
- Clipboard text, links, or code when clipboard capture is enabled.
- Manual memories, notes, Favorites, and other information you intentionally add.
- Local settings such as capture preferences, exclusions, update preferences, and onboarding state.
- Dates and times associated with captured activity.

The exact information available depends on macOS permissions and the source application. Memory Trail is intended to capture useful context, not the full contents of every application you use.

## 3. Accessibility permission

Memory Trail uses the macOS Accessibility permission to read supported active-application and focused-window context. This can include items such as browser page titles, Outlook subjects, Teams conversation titles, document names, and similar interface information exposed by macOS.

Accessibility permission is used for local activity capture. Memory Trail does not use this permission to create screen recordings or audio recordings.

If Accessibility permission is disabled, Memory Trail can continue running, but detailed focused-window context may be incomplete. The app may prompt you to enable Accessibility so the timeline can function as intended.

You can review or revoke this permission at any time in:

**System Settings → Privacy & Security → Accessibility**

## 4. Clipboard capture

Clipboard capture is optional and can be disabled in Memory Trail settings.

When enabled, supported copied text, links, or code may be stored in your local Memory Trail history. Memory Trail does not upload clipboard history to a Memory Trail server.

## 5. Excluded applications

Memory Trail allows you to exclude applications and processes from capture.

Sensitive applications such as **Passwords** and **Wallet** are excluded by default. Additional applications can be excluded in Settings.

Memory Trail attempts to honor configured exclusions for supported activity and clipboard capture. Because application behavior and macOS accessibility interfaces can change, users should still avoid copying or displaying sensitive information in applications they do not want represented in their local history.

## 6. Where your captured data is stored

Captured Memory Trail history is stored locally on your Mac using Apple platform storage technologies, including SwiftData. Preferences and app state may also be stored locally using standard macOS preference storage.

Memory Trail does not provide cloud synchronization for the captured timeline.

Your local activity history remains on the Mac unless you delete it, remove the relevant local app data, or otherwise erase the device/storage containing it.

The **Clear App Cache** feature resets temporary capture state and preferences. It is not intended to delete your saved timeline history.

## 7. Network connections and update checks

Memory Trail has **no data connectors** and does not connect to any external service to import, export, enrich, analyze, synchronize, or store your captured activity.

Memory Trail's captured timeline, clipboard history, files, paths, conversations, searches, Favorites, and manual memories are never included in update checks or GitHub requests.

The only routine external network activity built into Memory Trail is limited to GitHub-hosted resources for software maintenance and documentation, such as:

- Checking whether a newer Memory Trail release is available.
- Downloading a Memory Trail update after you choose to update.
- Opening the Memory Trail source repository, release page, or privacy policy.

These requests may expose ordinary network information to GitHub, such as your IP address, user agent, and request timestamp, as is typical when accessing a website or downloading a file. GitHub's handling of that information is governed by GitHub's own privacy practices.

Memory Trail does not embed GitHub account credentials in the application for update checking, does not require you to sign in to GitHub, and does not access your GitHub account or repositories through the app.

This limited GitHub connectivity is **not a data connector**. It is used only to check release metadata, download application updates you choose to install, and open public project documentation or source-code pages.

## 8. Analytics, tracking, advertising, profiling, and AI

Memory Trail does not include third-party analytics, advertising SDKs, behavioral advertising, telemetry services for captured activity, or a remote account system.

Memory Trail does not use your captured timeline to create advertising profiles.

Memory Trail does not scrape your activity for AI use. It does not send captured activity to OpenAI, Anthropic, Google, Microsoft, or any other AI provider; it does not use captured activity to train, fine-tune, evaluate, or improve AI models; and it does not create a cloud-based AI profile of your activity.

Memory Trail does not perform remote AI summarization or remote AI analysis of your captured history.

## 9. Sharing and sale of captured activity

Memory Trail does not sell your captured activity history.

Memory Trail does not transmit your captured activity history to advertisers or data brokers.

Because Memory Trail stores information locally, anyone who has sufficient access to your Mac or its storage may potentially access local application data. You are responsible for securing your Mac with appropriate macOS account, password, encryption, and device-security controls.

## 10. Data retention and deletion

Memory Trail retains local history until it is deleted through available app controls, removed with the app's local data, or erased from the Mac.

Deleting the application alone may not remove every local preference or database file maintained by macOS. If you want to fully remove local Memory Trail data, you may also need to remove the corresponding application-support, preference, or database data from your macOS user account.

## 11. Children

Memory Trail is a general-purpose productivity application and is not specifically designed to collect information from children. Because the app stores captured activity locally and does not operate a user-account service, Memory Trail does not intentionally create remote profiles of children.

## 12. Security

Memory Trail minimizes privacy risk by keeping captured activity local and avoiding a cloud timeline service. However, no software or local storage system can guarantee absolute security.

Users should keep macOS updated, use FileVault where appropriate, protect their user account, and configure exclusions for applications containing information they do not want stored in their local timeline.

## 13. Open-source verification

Memory Trail's source code is publicly available for review. This allows users and security researchers to inspect how the app captures, processes, stores, and updates information.

Source repository:

https://github.com/ram1424/Memory-Trail

## 14. Changes to this policy

This Privacy Policy may be updated when Memory Trail's functionality, storage model, permissions, or network behavior changes.

Material changes should be reflected in the public repository. The effective date at the top of this policy identifies the current version.

## 15. Contact and questions

Questions, privacy concerns, or reports about Memory Trail can be submitted through the Memory Trail GitHub repository:

https://github.com/ram1424/Memory-Trail/issues

---

## Plain-language summary

Memory Trail is built to keep your activity history **on your Mac**.

- **No connectors:** Memory Trail has no external data connectors of any kind.
- **No accounts:** there is no Memory Trail account, sign-in, remote profile, or account creation.
- **No cloud data processing:** captured activity is not processed, transmitted, synchronized, backed up, or stored on cloud services.
- **No AI scraping:** captured activity is not harvested for AI datasets, sent to AI providers, used for model training, or remotely summarized/analyzed by AI.
- **No analytics or advertising SDKs:** Memory Trail does not profile your activity for ads or telemetry.

The app may make limited requests to public GitHub resources only for update checks, update downloads, source-code links, releases, and this privacy policy. Those requests do not contain your captured timeline, clipboard history, files, conversations, searches, Favorites, or manual memories.
