# Memory Lane

**Memory Lane** is a private, local-first activity history for macOS that helps you retrace what you were working on throughout the day.

Instead of wondering:

- “What was I doing around 10:30?”
- “Which Outlook email was I reading before I opened Teams?”
- “What file was I working on yesterday?”
- “Where did I see that page?”

Memory Lane gives you a searchable chronological record of your work across supported apps.

> Memory Lane is designed to preserve the actual context it captures — such as an email subject, page title, filename, or window title — rather than rewriting or summarizing your timeline.

---

## What Memory Lane Does

### Timeline

Memory Lane builds a chronological timeline of activity from your Mac.

The Timeline can show:

- Applications you opened
- Browser pages and tab titles
- Outlook and Mail subject lines
- Teams conversations and windows
- OneNote pages
- Finder locations and filenames
- Word, Excel, PowerPoint, and Preview documents
- Clipboard text
- Manual memories
- Favorites

Timeline filters let you quickly switch between:

**All · Web · Email · Chat · Files · Clipboard · Favorites**

You can also choose between **Compact** and **Comfortable** layouts.

Double-click any Timeline item to open its full details in the right-side inspector.

---

## Ask Memory Lane

**Ask Memory Lane** lets you search your local history using natural-language-style questions.

Examples:

- What was I doing around 10:30 AM?
- What did I view before opening Teams?
- Find the Outlook email I viewed today
- Find the spreadsheet I worked on yesterday
- Show me Safari activity from this morning

Ask Memory Lane understands captured timestamps, app names, page titles, email subjects, filenames, file paths, and before/after relationships.

All searches run against your local Memory Lane history.

---

## App-Aware Capture

Memory Lane uses macOS Accessibility APIs and available application metadata to capture more useful context than just the application name.

### Web Browsers

Depending on what macOS exposes for the browser, Memory Lane can capture:

- Page and tab titles
- URLs when available
- Browser activity from Safari and other supported browsers such as Chrome and Firefox

### Email & Chat

Supported context includes:

- **Microsoft Outlook** — selected email subject lines
- **Apple Mail** — mail item subject/window context
- **Microsoft Teams** — conversation and window context
- Other supported applications when meaningful window metadata is available

### Files & Notes

Memory Lane can capture filenames, document titles, and local paths when macOS exposes them for apps such as:

- Finder
- Microsoft Word
- Microsoft Excel
- Microsoft PowerPoint
- Preview
- OneNote

This makes searches such as “budget spreadsheet from Tuesday” possible.

---

## Activity Overview

The Timeline includes an **Activity Overview** strip that provides a visual view of when activity occurred throughout the day.

It helps you quickly identify:

- Busy periods
- Quiet periods
- Approximate stretches of active work

---

## Clipboard History

Clipboard capture is enabled by default and can be disabled in Settings.

Memory Lane can remember copied:

- Text
- Links / URLs
- Code snippets

Large or unsupported clipboard content is ignored.

---

## Manual Memories

Use **Add Memory** to manually save something you want to remember.

Manual memories can be useful for:

- Notes
- Links
- Reminders
- Important context you want to preserve alongside automatic activity

---

## Favorites

Any Timeline item can be marked as a **Favorite**.

Favorites provide quick access to important:

- Pages
- Emails
- Files
- Notes
- Timeline events

---

## Details Inspector

Select an activity to view additional information in the right-side Details panel.

The inspector can show available information such as:

- Time
- Duration
- Application
- Activity type
- Captured details
- Source URL or file path
- Previous activity
- Actions such as Open App, Copy, and Favorite

The Details panel can be hidden when you want a wider Timeline view.

---

## Privacy & Control

Memory Lane is built as a **local-first** macOS application.

### Your data stays on your Mac

- Timeline history is stored locally using SwiftData.
- No Memory Lane account is required.
- No advertising SDK is included.
- No analytics SDK is included.

### Pause Capture

Pause and resume capture whenever you want.

### App Exclusions

Choose applications Memory Lane should ignore.

Sensitive apps such as **Passwords** and **Wallet** are excluded by default.

### Clipboard Control

Clipboard history can be turned off at any time.

### Clear App Cache

Memory Lane includes a cache reset option for clearing capture state and preferences without intentionally deleting your Timeline history.

---

## Accessibility Permission

Memory Lane requires macOS **Accessibility** permission for detailed focused-window context.

Without Accessibility permission, the app can still launch, but detailed capture such as selected Outlook subjects, browser context, and supported window information may be unavailable.

You can manage this permission in:

**System Settings → Privacy & Security → Accessibility**

---

## Menu Bar

Memory Lane can continue running from the macOS menu bar.

The menu bar provides quick access to core controls such as:

- Open Memory Lane
- Pause / Resume Capture
- Settings
- Quit

---

## Welcome Tutorial

A built-in onboarding tutorial walks through:

1. Memory Lane overview
2. Timeline
3. Ask Memory Lane
4. Browser, email, chat, file, notes, clipboard, manual memory, and Favorites capture
5. Privacy and controls
6. Accessibility setup

The tutorial can be replayed later from **Settings → Help**.

---

## Requirements

- macOS 14 or later
- Accessibility permission for detailed activity capture
- Xcode 16+ only if building from source

---

## Download

Download the current macOS DMG from the latest release:

**[Memory Lane v1.0.1](https://github.com/ram1424/Memory-Lane/releases/tag/v1.0.1)**

Direct DMG:

**[MemoryLane-1.0.1.dmg](https://github.com/ram1424/Memory-Lane/releases/download/v1.0.1/MemoryLane-1.0.1.dmg)**

---

## Website

Memory Lane also has a GitHub Pages site:

https://ram1424.github.io/Memory-Lane/

---

## Building from Source

Open Memory Lane.xcodeproj in Xcode.

Select the **Memory Lane** scheme and build for macOS.

Bundle identifier:

com.ram1424.memorylane

---

## Philosophy

Memory Lane is intended to answer a simple question:

> **“What was I doing?”**

It does that by preserving useful local context from your workday and making it easy to retrace later.
