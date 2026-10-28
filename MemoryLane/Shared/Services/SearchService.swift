import Foundation

struct SmartWorkSession: Identifiable {
    let id: UUID
    let items: [MemoryItem]
    let start: Date
    let end: Date
    let duration: TimeInterval
    let title: String
    let summary: String
    let apps: [String]

    init(items: [MemoryItem], now: Date = .now) {
        let ordered = items.sorted { $0.createdAt < $1.createdAt }
        self.items = ordered
        self.id = ordered.first?.id ?? UUID()
        self.start = ordered.first?.createdAt ?? now

        var total: TimeInterval = 0
        for (index, item) in ordered.enumerated() {
            let nextDate: Date
            if index + 1 < ordered.count {
                nextDate = ordered[index + 1].createdAt
            } else {
                nextDate = min(now, item.createdAt.addingTimeInterval(8 * 60))
            }
            total += min(max(0, nextDate.timeIntervalSince(item.createdAt)), 30 * 60)
        }

        self.duration = total
        self.end = ordered.last?.createdAt.addingTimeInterval(min(8 * 60, max(60, total / Double(max(ordered.count, 1))))) ?? start
        self.apps = SearchService.orderedUnique(ordered.map(\.sourceApp).filter { !$0.isEmpty })
        self.title = SearchService.sessionTitle(for: ordered)
        self.summary = SearchService.sessionSummary(title: self.title, items: ordered, apps: self.apps, duration: total)
    }
}

struct DailyRecap {
    let date: Date
    let totalDuration: TimeInterval
    let sessions: [SmartWorkSession]
    let topApps: [(name: String, count: Int)]
    let busiestHour: Int?
    let favoriteCount: Int
    let summary: String
}

struct MemoryLaneAnswer {
    let summary: String
    let items: [MemoryItem]
    let sessions: [SmartWorkSession]
    let interpretedQuery: String
}

enum SearchService {
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "around", "at", "before", "after", "did", "do",
        "doing", "find", "for", "from", "i", "in", "into", "is", "it", "me",
        "my", "of", "on", "open", "opened", "opening", "or", "show", "the",
        "this", "to", "today", "was", "were", "what", "when", "where", "with",
        "yesterday", "view", "viewed", "working"
    ]

    private static let genericTerms: Set<String> = stopWords.union([
        "microsoft", "apple", "google", "safari", "outlook", "teams", "finder",
        "onenote", "word", "excel", "powerpoint", "preview", "chrome", "mail",
        "application", "focused", "window", "page", "item", "activity", "opened"
    ])

    static func tokens(for query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func meaningfulTokens(for text: String) -> [String] {
        tokens(for: text)
            .filter { $0.count > 2 && !genericTerms.contains($0) && Int($0) == nil }
    }

    static func matches(_ item: MemoryItem, query: String) -> Bool {
        matches(item, tokens: tokens(for: query))
    }

    static func matches(_ item: MemoryItem, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = item.searchableText
        return tokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    static func smartSessions(from items: [MemoryItem], now: Date = .now) -> [SmartWorkSession] {
        let relevant = items
            .filter { $0.sourceKind == .appActivity || $0.sourceKind == .file || $0.sourceKind == .link }
            .sorted { $0.createdAt < $1.createdAt }

        guard let first = relevant.first else { return [] }

        var groups: [[MemoryItem]] = [[first]]

        for item in relevant.dropFirst() {
            guard let previous = groups.last?.last else { continue }
            let gap = item.createdAt.timeIntervalSince(previous.createdAt)

            if shouldJoin(previous: previous, current: item, gap: gap) {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }

        return groups
            .filter { !$0.isEmpty }
            .map { SmartWorkSession(items: $0, now: now) }
            .sorted { $0.start > $1.start }
    }

    static func dailyRecap(for date: Date, items: [MemoryItem], now: Date = .now) -> DailyRecap {
        let calendar = Calendar.current
        let dayItems = items.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
        let sessions = smartSessions(from: dayItems, now: now)
        let total = sessions.reduce(0) { $0 + $1.duration }

        let appCounts = Dictionary(grouping: dayItems.filter { !$0.sourceApp.isEmpty }, by: \.sourceApp)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }

        let hourCounts = Dictionary(grouping: dayItems) {
            calendar.component(.hour, from: $0.createdAt)
        }.mapValues(\.count)

        let busiest = hourCounts.max {
            if $0.value == $1.value { return $0.key > $1.key }
            return $0.value < $1.value
        }?.key

        let favoriteCount = dayItems.filter(\.isFavorite).count
        let topNames = appCounts.prefix(3).map(\.name)
        let appPhrase = naturalList(topNames)
        let durationText = compactDuration(total)

        var parts: [String] = []
        if !durationText.isEmpty {
            parts.append("Memory Lane reconstructed about \(durationText) of active work")
        }
        if !appPhrase.isEmpty {
            parts.append("mostly across \(appPhrase)")
        }
        if !sessions.isEmpty {
            parts.append("in \(sessions.count) work session\(sessions.count == 1 ? "" : "s")")
        }

        let summary = parts.isEmpty
            ? "No substantial work activity was captured for this day."
            : parts.joined(separator: " ") + "."

        return DailyRecap(
            date: date,
            totalDuration: total,
            sessions: sessions,
            topApps: Array(appCounts.prefix(5)),
            busiestHour: busiest,
            favoriteCount: favoriteCount,
            summary: summary
        )
    }

    static func ask(_ query: String, memories: [MemoryItem], now: Date = .now) -> MemoryLaneAnswer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MemoryLaneAnswer(
                summary: "Ask about a time, app, file, page, email, chat, or project in your local Memory Lane history.",
                items: [],
                sessions: [],
                interpretedQuery: ""
            )
        }

        let lower = trimmed.lowercased()
        let calendar = Calendar.current
        let targetDay: Date? = {
            if lower.contains("yesterday") {
                return calendar.date(byAdding: .day, value: -1, to: now)
            }
            if lower.contains("today") {
                return now
            }
            return nil
        }()

        var candidates = memories
        if let targetDay {
            candidates = candidates.filter { calendar.isDate($0.createdAt, inSameDayAs: targetDay) }
        }

        let appFilter = detectedApp(in: lower)
        if let appFilter, !lower.contains("before") && !lower.contains("after") {
            candidates = candidates.filter { item in
                let haystack = "\(item.sourceApp) \(item.sourceBundleID)".lowercased()
                return appFilter.aliases.contains { haystack.contains($0) }
            }
        }

        if let relationAnswer = relationalAnswer(query: lower, candidates: candidates, now: now) {
            return relationAnswer
        }

        if let requestedTime = parsedTime(from: lower, on: targetDay ?? now) {
            let window: TimeInterval = lower.contains("around") || lower.contains("about") ? 45 * 60 : 30 * 60
            candidates = candidates.filter { abs($0.createdAt.timeIntervalSince(requestedTime)) <= window }
        }

        let queryTokens = meaningfulTokens(for: trimmed)
        let ranked = candidates
            .map { item -> (MemoryItem, Int) in
                let text = item.searchableText
                var score = 0
                for token in queryTokens {
                    if text.localizedStandardContains(token) { score += 20 }
                    if item.title.lowercased().localizedStandardContains(token) { score += 15 }
                }
                if item.sourceKind == .file { score += 5 }
                if item.isFavorite { score += 3 }
                return (item, score)
            }
            .filter { queryTokens.isEmpty || $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 { return $0.0.createdAt > $1.0.createdAt }
                return $0.1 > $1.1
            }
            .prefix(12)
            .map(\.0)

        let results: [MemoryItem]
        if ranked.isEmpty && queryTokens.isEmpty {
            results = Array(candidates.sorted { $0.createdAt > $1.createdAt }.prefix(12))
        } else {
            results = ranked
        }

        let sessions = smartSessions(from: results, now: now)
        let summary = answerSummary(query: trimmed, items: results, sessions: sessions)

        return MemoryLaneAnswer(
            summary: summary,
            items: results,
            sessions: sessions,
            interpretedQuery: interpretationText(query: trimmed, targetDay: targetDay, appFilter: appFilter)
        )
    }

    static func sessionTitle(for items: [MemoryItem]) -> String {
        guard !items.isEmpty else { return "Work Session" }

        var phraseScores: [String: Int] = [:]
        var displayPhrase: [String: String] = [:]

        for item in items {
            let rawCandidates = phraseCandidates(from: item)
            for phrase in rawCandidates {
                let key = phrase.lowercased()
                phraseScores[key, default: 0] += phrase.count + 25
                displayPhrase[key] = phrase
            }
        }

        if let best = phraseScores.max(by: { $0.value < $1.value }),
           best.value >= 35,
           let display = displayPhrase[best.key] {
            return String(display.prefix(70))
        }

        let wordCounts = Dictionary(grouping: items.flatMap { meaningfulTokens(for: "\($0.title) \($0.body)") }, by: { $0 })
            .mapValues(\.count)
            .filter { $0.value >= 2 }

        if let token = wordCounts.max(by: { $0.value < $1.value })?.key {
            return token.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }

        if let meaningful = items.reversed().first(where: { !$0.title.hasPrefix("Opened ") && !$0.title.isEmpty }) {
            return String(meaningful.title.prefix(70))
        }

        let apps = orderedUnique(items.map(\.sourceApp))
        return apps.first.map { "\($0) Session" } ?? "Work Session"
    }

    static func sessionSummary(title: String, items: [MemoryItem], apps: [String], duration: TimeInterval) -> String {
        let durationText = compactDuration(duration)
        let appPhrase = naturalList(Array(apps.prefix(3)))
        let activityCount = items.filter { !$0.title.hasPrefix("Opened ") }.count

        if !durationText.isEmpty && !appPhrase.isEmpty {
            return "You spent about \(durationText) across \(appPhrase) working on \(title), with \(activityCount) captured activit\(activityCount == 1 ? "y" : "ies")."
        }
        if !appPhrase.isEmpty {
            return "A work session across \(appPhrase) focused on \(title)."
        }
        return "A work session focused on \(title)."
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return "<1m" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func shouldJoin(previous: MemoryItem, current: MemoryItem, gap: TimeInterval) -> Bool {
        if !Calendar.current.isDate(previous.createdAt, inSameDayAs: current.createdAt) { return false }
        if gap < 0 { return false }
        if gap <= 12 * 60 { return true }
        if gap > 35 * 60 { return false }

        let previousTokens = Set(meaningfulTokens(for: previous.searchableText))
        let currentTokens = Set(meaningfulTokens(for: current.searchableText))
        let shared = previousTokens.intersection(currentTokens)

        if !shared.isEmpty { return true }
        if previous.sourceApp == current.sourceApp && gap <= 22 * 60 { return true }

        let productivityApps = ["outlook", "teams", "safari", "finder", "onenote", "word", "excel", "powerpoint", "mail", "preview"]
        let a = "\(previous.sourceApp) \(previous.sourceBundleID)".lowercased()
        let b = "\(current.sourceApp) \(current.sourceBundleID)".lowercased()
        let bothProductivity = productivityApps.contains { a.contains($0) } && productivityApps.contains { b.contains($0) }
        return bothProductivity && gap <= 18 * 60
    }

    private static func phraseCandidates(from item: MemoryItem) -> [String] {
        var values = [item.title]
        if let sourceURL = item.sourceURL,
           let url = URL(string: sourceURL),
           url.isFileURL {
            values.append(url.deletingPathExtension().lastPathComponent)
            values.append(url.deletingLastPathComponent().lastPathComponent)
        }

        var output: [String] = []
        for value in values {
            let pieces = value.components(separatedBy: CharacterSet(charactersIn: "|—–:"))
            for piece in pieces {
                let cleaned = piece
                    .replacingOccurrences(of: "Re:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Fwd:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let lower = cleaned.lowercased()
                guard cleaned.count >= 4,
                      cleaned.count <= 90,
                      !genericTerms.contains(lower),
                      !lower.hasPrefix("opened ")
                else { continue }

                output.append(cleaned)
            }
        }
        return output
    }

    private struct DetectedApp {
        let displayName: String
        let aliases: [String]
    }

    private static func detectedApp(in query: String) -> DetectedApp? {
        let map: [(String, [String])] = [
            ("Outlook", ["outlook"]),
            ("Teams", ["teams", "msteams"]),
            ("Safari", ["safari"]),
            ("Finder", ["finder"]),
            ("OneNote", ["onenote"]),
            ("Word", ["word"]),
            ("Excel", ["excel"]),
            ("PowerPoint", ["powerpoint"]),
            ("Preview", ["preview"]),
            ("Mail", ["mail"]),
            ("Chrome", ["chrome"])
        ]

        for (name, aliases) in map where aliases.contains(where: { query.contains($0) }) {
            return DetectedApp(displayName: name, aliases: aliases)
        }
        return nil
    }

    private static func relationalAnswer(query: String, candidates: [MemoryItem], now: Date) -> MemoryLaneAnswer? {
        let before = query.contains("before")
        let after = query.contains("after")
        guard before || after else { return nil }

        let relationshipToken = before ? "before" : "after"
        let pieces = query.components(separatedBy: relationshipToken)
        let leftText = pieces.first ?? ""
        let rightText = pieces.dropFirst().joined(separator: relationshipToken)

        // The app named after "before/after" is the anchor. This correctly
        // interprets questions such as "Outlook email before opening Teams".
        guard let targetApp = detectedApp(in: rightText) ?? detectedApp(in: query) else {
            return nil
        }
        let desiredApp = detectedApp(in: leftText)

        let ordered = candidates.sorted { $0.createdAt < $1.createdAt }
        guard let targetIndex = ordered.lastIndex(where: { item in
            let haystack = "\(item.sourceApp) \(item.sourceBundleID)".lowercased()
            return targetApp.aliases.contains { haystack.contains($0) }
        }) else {
            return MemoryLaneAnswer(
                summary: "I couldn't find a captured \(targetApp.displayName) activity matching that question.",
                items: [],
                sessions: [],
                interpretedQuery: "Looking for activity relative to \(targetApp.displayName)"
            )
        }

        let target = ordered[targetIndex]
        let window: [MemoryItem]

        if before {
            let lowerBound = target.createdAt.addingTimeInterval(-60 * 60)
            window = Array(ordered.filter {
                $0.createdAt < target.createdAt && $0.createdAt >= lowerBound
            }.suffix(12))
        } else {
            let upperBound = target.createdAt.addingTimeInterval(60 * 60)
            window = Array(ordered.filter {
                $0.createdAt > target.createdAt && $0.createdAt <= upperBound
            }.prefix(12))
        }

        var result = before ? Array(window.reversed()) : window

        if let desiredApp, desiredApp.displayName != targetApp.displayName {
            let appMatches = result.filter { item in
                let haystack = "\(item.sourceApp) \(item.sourceBundleID)".lowercased()
                return desiredApp.aliases.contains { haystack.contains($0) }
            }
            if !appMatches.isEmpty {
                result = appMatches
            }
        }

        result = Array(result.prefix(8))
        let relationship = before ? "before" : "after"
        let summary: String

        if let nearest = result.first {
            summary = "Immediately \(relationship) the \(targetApp.displayName) activity at \(target.createdAt.formatted(date: .omitted, time: .shortened)), Memory Lane found \(nearest.sourceApp): “\(nearest.title)”."
        } else {
            summary = "I found the \(targetApp.displayName) activity, but there wasn't a matching captured activity within an hour \(relationship) it."
        }

        return MemoryLaneAnswer(
            summary: summary,
            items: result,
            sessions: smartSessions(from: result, now: now),
            interpretedQuery: "Activity \(relationship) \(targetApp.displayName) at \(target.createdAt.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    private static func parsedTime(from query: String, on day: Date) -> Date? {
        let pattern = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = query as NSString
        let matches = regex.matches(in: query, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let hourString = ns.substring(with: match.range(at: 1))
            guard var hour = Int(hourString), hour >= 0, hour <= 23 else { continue }

            var minute = 0
            if match.range(at: 2).location != NSNotFound {
                minute = Int(ns.substring(with: match.range(at: 2))) ?? 0
            }
            guard minute < 60 else { continue }

            if match.range(at: 3).location != NSNotFound {
                let meridian = ns.substring(with: match.range(at: 3)).lowercased()
                guard hour >= 1, hour <= 12 else { continue }
                if meridian == "pm" && hour != 12 { hour += 12 }
                if meridian == "am" && hour == 12 { hour = 0 }
            } else if hour <= 7 && (query.contains("afternoon") || query.contains("evening")) {
                hour += 12
            }

            var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            if let date = Calendar.current.date(from: components) {
                return date
            }
        }

        return nil
    }

    private static func answerSummary(query: String, items: [MemoryItem], sessions: [SmartWorkSession]) -> String {
        guard !items.isEmpty else {
            return "I couldn't find a strong match in the local timeline for “\(query)”. Try an app name, project/file name, or a time such as “around 10:30 AM.”"
        }

        let apps = orderedUnique(items.map(\.sourceApp))
        let appPhrase = naturalList(Array(apps.prefix(3)))
        let timeRange: String = {
            let ordered = items.sorted { $0.createdAt < $1.createdAt }
            guard let first = ordered.first, let last = ordered.last else { return "" }
            if Calendar.current.isDate(first.createdAt, inSameDayAs: last.createdAt) {
                return "\(first.createdAt.formatted(date: .omitted, time: .shortened))–\(last.createdAt.formatted(date: .omitted, time: .shortened))"
            }
            return "\(first.createdAt.formatted(date: .abbreviated, time: .shortened)) through \(last.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }()

        if let session = sessions.first {
            return "I found \(items.count) relevant activit\(items.count == 1 ? "y" : "ies") around \(timeRange). The strongest match is the “\(session.title)” session across \(appPhrase)."
        }

        return "I found \(items.count) relevant activit\(items.count == 1 ? "y" : "ies") around \(timeRange) across \(appPhrase)."
    }

    private static func interpretationText(query: String, targetDay: Date?, appFilter: DetectedApp?) -> String {
        var parts: [String] = []
        if let targetDay {
            parts.append(targetDay.formatted(date: .abbreviated, time: .omitted))
        }
        if let appFilter {
            parts.append(appFilter.displayName)
        }
        let keywords = meaningfulTokens(for: query).prefix(4)
        if !keywords.isEmpty {
            parts.append(keywords.joined(separator: ", "))
        }
        return parts.isEmpty ? "Local timeline search" : parts.joined(separator: " · ")
    }

    private static func naturalList(_ values: [String]) -> String {
        switch values.count {
        case 0: return ""
        case 1: return values[0]
        case 2: return "\(values[0]) and \(values[1])"
        default:
            return values.dropLast().joined(separator: ", ") + ", and " + values.last!
        }
    }
}
