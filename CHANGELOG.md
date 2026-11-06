# Memory Trails Changelog

## 1.4 (Build 1) - November 5, 2026

Memory Trails 1.4 is a polished release focused on reliable Outlook capture, clearer activity history, more useful Ask Memory Trails results, and a cleaner overall experience.

### Outlook Capture & Reliability

- Separate capture paths for Classic Outlook and New Outlook.
- Improved New Outlook reliability across column, bottom reading-pane, full-width, Search, Sent, custom-folder, and open-message layouts.
- Subject and sender capture is anchored to the actual message header, with Outlook navigation, account, toolbar, recipient, Copilot, and presence metadata excluded.
- Better handling for repeated messages, same-subject emails, truncated list subjects, slower-loading headers, external senders, service accounts, and email-address-style subjects.
- Calendar and meeting invitations recognize organizer-style sender fields.
- Outlook timeline entries display sender context inline as `Subject  From: Sender`.

### Today & Timeline

- Clearer activity-first Today layout with summary metrics and filters.
- Restored activity details with single-click selection, double-click reopening, and a visible Close control.
- Added Go to Today for easier navigation back to the current day.
- Improved Top Apps Today label handling.

### Ask Memory Trails

- Removed arbitrary Supporting Activity result-count limits.
- Fuller day-level conversation and email history can be returned when it matches the query.
- Added a floating Back to Top control for long results.
- Quick-start prompts use distinct icons for email, conversations, websites, files, projects, and time-based activity.
- Supporting Activity remains full-width and shows the number of matching items.

### Insights, Favorites & Consistency

- Cleaner Insights dashboard with Top Apps, Key Takeaways, activity patterns, and recent files.
- Clearer Favorites context and empty state.
- More consistent visual structure across Insights, Favorites, Clipboard History, Ask Memory Trails, and Settings.

### Storage, History & Export

- Local activity is stored in `MemoryTrail.store` inside Application Support.
- Default local history retention remains 30 days.
- Added controls to clear the last week, last month, or all history.
- JSON export includes filename, item count, file size, and Show in Finder.
- Simplified history and export confirmations.

### Settings, Updates & Privacy

- Cleaner Settings layout with privacy, exclusions, and storage controls easier to reach.
- Refined update confirmation and version/build presentation.
- Activity continues to be sourced, processed, and stored locally on the Mac.
- No cloud timeline sync, external data connectors, advertising SDKs, or AI timeline summarization.
- Passwords and Wallet remain excluded by default.
- Source code remains available for review and verification.

---

## 1.3 (Build 12) - November 5, 2026

Memory Trails 1.3 focuses on reliable Outlook activity capture, a clearer timeline experience, stronger local history controls, and overall polish.

### What’s New Reorganization

- Reorganized the in-app **What’s New** screen into a cleaner release-style flow.
- Consolidated the many Outlook implementation bullets into one concise **Outlook Capture & Reliability** section.
- Separated the rest of the release into **Today & Timeline**, **Ask Memory Trails**, **Insights, Favorites & Consistency**, **Storage, History & Export**, **Settings, Updates & Polish**, and **Privacy First**.
- Removed repetitive technical wording while preserving the user-facing improvements included in Memory Trails 1.3.

### New Outlook Fail-Closed Header Fix

- Fixed a Build 10 regression where the last-resort non-column fallback scanned the entire Outlook window. That allowed navigation/account chrome such as `All Accounts` to be paired with a real sender and logged as if it were an email subject.
- Reading-pane parsing now requires either an explicit semantic reading/message pane or a structural Message Header container.
- If neither is exposed, Memory Trails falls back to the selected Outlook message object/row instead of scanning unrelated Outlook UI.
- Added `All Accounts`, `All Mailboxes`, `All Folders`, and account-list labels to the Outlook navigation-chrome filter.
- Added the same navigation-chrome validation to the clicked-subject fallback so invalid labels cannot re-enter after reading-pane rejection.
- `Presence Unknown` and `Unknown Presence` are now treated as Outlook presence metadata and removed from the captured From value.
- The valid non-column/bottom-pane geometry improvements from Build 10 remain in place when Outlook exposes a trustworthy message pane/header.

### New Outlook Non-Column Layout Fix

- Confirmed a layout-specific bug: Column Layout/right-side reading pane worked more reliably because Memory Trails still contained geometry assumptions that the message list was on the left and the message header was in the right side of the Outlook window.
- Removed the horizontal left-side cutoff from clicked message-row identity. New Outlook can now identify the actual selected row when the message list spans the full width above a bottom reading pane.
- Increased selected-row Accessibility scanning from 500 to 1,500 elements for the larger hierarchy used by non-column layouts.
- Selected-row identity now comes from Outlook's `AXSelectedRows` first and includes row frame information, making it layout-independent and better at distinguishing repeated messages.
- Semantic reading-pane frames are honored wherever Outlook positions them: right, bottom, fill-screen, or other supported locations.
- Structural Message header fallback now anchors the capture region to the header's actual vertical position instead of assuming the pane begins at the top of the Outlook window.
- Wide or lower Message header structures are treated as bottom/full-width layouts and scanned across the available width.
- The final fallback is layout-neutral rather than hard-coded to the right 55% of the window.
- Subject and sender candidates near the detected structural Message header receive an additional score boost so message-list text cannot outrank the opened message.
- Increased allowed vertical Subject-to-From spacing for non-column layouts where Outlook uses taller header spacing.

### New Outlook Selection-State Reliability

- Fixed an architectural bug where New Outlook was re-detected from transient UI labels on every capture. The same New Outlook process could therefore be treated as New in Inbox but Classic in Search, Sent, custom folders, or full-width/open-message layouts.
- Once New Outlook is positively identified for the running Outlook process, Memory Trails now keeps that mode for the lifetime of the process.
- Broadened New Outlook detection to recognize web-content roles, reading/message pane identifiers, and structural Message header signals, with a larger Accessibility scan budget.
- Carries the clicked message-row identity into the asynchronous reading-pane capture without making row detection a prerequisite for capture.
- Distinct emails with identical Subject and From values can now be logged independently when the clicked row proves the selection changed.
- Merges reading-pane, selected-object, and selected-row identities rather than allowing one stale identity source to override the others.
- Subject comparison now treats truncated list-row subjects as compatible with the full visible reading-pane subject.
- Removed the Outlook-specific 150 ms logging throttle. Outlook duplicate suppression now uses content signatures plus selection identity, avoiding timing-based loss.
- The 1.25-second Outlook poll remains as a fallback for keyboard navigation and other selection changes that do not produce a clean mouse event.
- Confirmed that the timeline noise filter only hides known Outlook chrome such as Inbox/Calendar/URLs; ordinary valid email subjects are not removed after storage.

### Outlook Calendar Invites & Timeline Sender

- Calendar and meeting invitation emails now recognize **Organizer**, **Meeting Organizer**, **Organized by**, **Organised by**, and **Invited by** as valid sender fields equivalent to From.
- The invite sender logic is shared between New Outlook reading-pane capture and Classic/general Outlook Accessibility capture.
- Meeting response controls such as Accept, Tentative, Decline, Propose New Time, response options, and response-state labels are excluded from subject candidates.
- Outlook timeline rows now show the sender inline with the subject in the form `Subject  From: Sender`.
- The underlying stored subject and sender remain separate, so details/search behavior is preserved.

### New Outlook False-Filter Fix

- Removed the content-shape rule that incorrectly rejected legitimate subjects simply because they looked like email addresses.
- Explicit Subject fields, AppleScript-selected subjects, and trusted visible New Outlook subject positions can now preserve email-address-shaped subjects.
- Outlook badges such as External, External Sender, Guest, Internal, and similar security labels are treated as UI metadata rather than subject/sender candidates.
- Subject selection now requires the subject to be positioned above the confirmed sender line, reducing the need for risky text-content filtering.
- Sender parsing now tolerates angle-bracket and ellipsis characters that New Outlook may expose in sender display strings.

### Ask Memory Trails Quick-Start Icons

- Replaced category-reused quick-start icons with prompt-specific SF Symbols.
- Email uses an envelope while conversations use paired chat bubbles, making those two prompts visually distinct.
- Websites, files, projects, weekly activity, recent activity, and earlier/today prompts now use icons that match their actual intent.

### Ask Memory Trails Navigation & Supporting Activity

- Removed the arbitrary Supporting Activity count limits from general searches, Outlook email searches, and before/after activity searches.
- Supporting Activity can now contain the full set of locally stored activity matching the interpreted query and its date/app/content filters.
- Added a floating **Back to Top** control to Ask Memory Trails so long result sets can be navigated without manually scrolling back to the query area.
- Added a clearly visible **Close** button directly in the expanded activity header. The existing toolbar close control remains available.

### New Outlook Subject Reliability Fix

- Added one centralized Outlook header-metadata classifier used by all subject extraction paths.
- Strings such as `Sent on: Today at 9:27 AM`, Sent/Received timestamps, recipient lines, date/time labels, presence states, and other header metadata can no longer become the captured subject.
- Expanded the valid subject/header region while keeping sender-relative geometry as the primary structure check, improving capture of wrapped and lower-positioned subjects.
- New Outlook now retains timestamps found inside Sent/Received metadata for message identity instead of discarding them.
- If the visible message header does not yield a complete valid Subject/From pair, Memory Trails falls back to the selected Outlook message object and then the selected row instead of ignoring the email.
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

### Ask Memory Trails, Favorites & App Consistency

- Broader day-level conversation questions can return the complete matching conversation history instead of stopping at a small fixed result set.
- Supporting Activity is full-width, easier to scan, and shows the number of returned items.
- Favorites has clearer saved-item context and a more useful empty state.
- Ask Memory Trails, Favorites, Clipboard History, Insights, and Settings use more consistent headers, cards, spacing, and visual treatment.

### Storage, History & Export

- Local activity uses the clearly named `MemoryTrail.store` database in Memory Trails’ Application Support folder.
- Default local history retention is 30 days.
- Added controls to clear the last week, last month, or all history.
- JSON export remains local and now provides a cleaner completion view with filename, item count, file size, and Show in Finder.
- Simplified export and history confirmation screens.

### Settings & Updates

- Reorganized Settings into a cleaner continuous card layout.
- Moved privacy, exclusions, and storage/history controls higher for easier access.
- Refined the update confirmation experience while keeping the simple up-to-date flow.
- About Memory Trails now presents version and build information more clearly.

### Privacy

- Activity continues to be sourced, processed, and stored locally on the Mac.
- No cloud timeline sync or external data connectors.
- No analytics or advertising SDKs.
- No AI summarization of the timeline.
- Passwords and Wallet remain excluded by default.
- App/process exclusion and capture controls remain available.
- Source code remains available for review and verification.
