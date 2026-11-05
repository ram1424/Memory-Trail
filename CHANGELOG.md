# Memory Trail Changelog

## 1.3 (Build 4) - November 5, 2026

Memory Trail 1.3 focuses on reliable Outlook activity capture, a clearer timeline experience, stronger local history controls, and overall polish.

### New Outlook Subject Reliability Fix

- Added one centralized Outlook header-metadata classifier used by all subject extraction paths.
- Strings such as `Sent on: Today at 9:27 AM`, Sent/Received timestamps, recipient lines, date/time labels, presence states, and other header metadata can no longer become the captured subject.
- Expanded the valid subject/header region while keeping sender-relative geometry as the primary structure check, improving capture of wrapped and lower-positioned subjects.
- New Outlook now retains timestamps found inside Sent/Received metadata for message identity instead of discarding them.
- If the visible message header does not yield a complete valid Subject/From pair, Memory Trail falls back to the selected Outlook message object and then the selected row instead of ignoring the email.
- Fixed an internal de-duplication inconsistency so the stored last-message key now uses the same identity + subject + sender format as the capture scheduler.

### New Outlook Full-Width Header Fix

- Added support for New Outlook messages whose open-message header spans most or all of the Outlook window instead of living in the traditional right-side reading pane.
- Removed premature left-side Accessibility pruning before the message-pane layout is known.
- New Outlook now detects semantic reading/message panes anywhere in the focused Outlook window and can use the structural Message header container to establish the correct scan region.
- Message de-duplication now combines identity with the visible subject and sender so a stale/constant row identity cannot suppress a different email.
- Reading-pane identity derived from subject/sender/timestamp is preferred over an unverified generic selected-row identity.

### Outlook Capture Reliability Patch

- New Outlook now performs a validated selected-message check on every click instead of requiring a specific Accessibility row shape before capture starts.
- Removed the hard exact-match dependency between message-list text and the right-pane subject; truncated or differently formatted list subjects no longer cause valid emails to be dropped.
- Extended conditional retry coverage for messages whose reading pane or sender metadata loads slowly.
- Retains selected-row identity independently of subject parsing to distinguish separate messages that share the same subject and sender.
- Classic Outlook keeps the proven clicked-message path and gains a validated fallback when the clicked row does not expose a usable subject.

### Outlook Capture

- Restored the proven Classic Outlook capture path so the selected message supplies the correct subject and sender.
- Separated Classic Outlook and New Outlook extraction logic so changes to one interface do not regress the other.
- New Outlook now reads only the actual message subject and From field from the right-side message header.
- Ignores Outlook UI chrome including Delete, Archive, Move, Flag, search controls, title bars, Message header containers, recipient controls, Copilot summary labels, body headings, and other non-message elements.
- Uses the confirmed sender/header region to identify the correct New Outlook subject.
- Removes sender presence states such as Available, Busy, Away, and Offline.
- Supports a broader range of senders, including external senders, service accounts, distribution lists, email-only senders, long display names, and via sender formats.
- Prevents separate messages with the same subject from being incorrectly treated as the same activity.
- Adds stale-reading-pane protection and faster Outlook capture behavior.

### Today, Timeline & Insights

- Refined Today into a clearer activity-first layout with summary metrics, filters, and a more prominent timeline.
- Restored the right-side activity details panel.
- Single-clicking an activity updates the details panel; double-clicking can reopen it when hidden.
- Added Go to Today when browsing earlier dates.
- Improved Top Apps Today so longer application names fit more cleanly.
- Refined Insights with more consistent cards and useful context including Top Apps, Key Takeaways, and recent files/documents.

### Ask Memory Trail, Favorites & App Consistency

- Broader day-level conversation questions can return the complete matching conversation history instead of stopping at a small fixed result set.
- Supporting Activity is full-width, easier to scan, and shows the number of returned items.
- Favorites has clearer saved-item context and a more useful empty state.
- Ask Memory Trail, Favorites, Clipboard History, Insights, and Settings use more consistent headers, cards, spacing, and visual treatment.

### Storage, History & Export

- Local activity uses the clearly named `MemoryTrail.store` database in Memory Trail's Application Support folder.
- Default local history retention is 30 days.
- Added controls to clear the last week, last month, or all history.
- JSON export remains local and now provides a cleaner completion view with filename, item count, file size, and Show in Finder.
- Simplified export and history confirmation screens.

### Settings & Updates

- Reorganized Settings into a cleaner continuous card layout.
- Moved privacy, exclusions, and storage/history controls higher for easier access.
- Refined the update confirmation experience while keeping the simple up-to-date flow.
- About Memory Trail now presents version and build information more clearly.

### Privacy

- Activity continues to be sourced, processed, and stored locally on the Mac.
- No cloud timeline sync or external data connectors.
- No analytics or advertising SDKs.
- No AI summarization of the timeline.
- Passwords and Wallet remain excluded by default.
- App/process exclusion and capture controls remain available.
- Source code remains available for review and verification.
