import Foundation

struct DailyRecap {
    let date: Date
    let totalDuration: TimeInterval
    let topApps: [(name: String, count: Int)]
    let busiestHour: Int?
    let favoriteCount: Int
    let summary: String
}

struct MemoryLaneAnswer {
    let summary: String
    let items: [MemoryItem]
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

    static func dailyRecap(for date: Date, items: [MemoryItem], now: Date = .now) -> DailyRecap {
        let calendar = Calendar.current
        let dayItems = items.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
        let relevantItems = dayItems.filter {
            $0.sourceKind == .appActivity || $0.sourceKind == .file || $0.sourceKind == .link
        }
        let total = reconstructedActivityDuration(from: relevantItems, now: now)

        let appCounts = Dictionary(
            grouping: relevantItems.filter { !$0.sourceApp.isEmpty },
            by: .sourceApp
        )
        .map { (name: $0.key, count: $0.value.count) }
        .sorted {
            if $0.count == $1.count { return $0.name < $1.name }
            return $0.count > $1.count
        }

        let hourCounts = Dictionary(grouping: relevantItems) {
            calendar.component(.hour, from: $0.createdAt)
        }.mapValues(.count)

        let busiest = hourCounts.max {
            if $0.value == $1.value { return $0.key > $1.key }
            return $0.value < $1.value
        }?.key

        let favoriteCount = dayItems.filter(.isFavorite).count
        let topNames = appCounts.prefix(3).map(.name)
        let appPhrase = naturalList(topNames)
        let durationText = compactDuration(total)

        var parts: [String] = []
        if !durationText.isEmpty {
            parts.append("Memory Lane reconstructed about \(durationText) of active work")
        }
        if !appPhrase.isEmpty {
            parts.append("mostly across \(appPhrase)")
        }

        let summary = parts.isEmpty
            ? "No substantial work activity was captured for this day."
            : parts.joined(separator: " ") + "."

        return DailyRecap(
            date: date,
            totalDuration: total,
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

        if let relationAnswer = relationalAnswer(query: lower, candidates: candidates) {
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
            .map(.0)

        let results: [MemoryItem]
        if ranked.isEmpty && queryTokens.isEmpty {
            results = Array(candidates.sorted { $0.createdAt > $1.createdAt }.prefix(12))
        } else {
            results = ranked
        }

        return MemoryLaneAnswer(
            summary: answerSummary(query: trimmed, items: results),
            items: results,
            interpretedQuery: interpretationText(query: trimmed, targetDay: targetDay, appFilter: appFilter)
        )
    }

    static func compactDuration(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return "<1m" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func reconstructedActivityDuration(from items: [MemoryItem], now: Date = .now) -> TimeInterval {
        let ordered = items.sorted { $0.createdAt < $1.createdAt }
        guard !ordered.isEmpty else { return 0 }

        var total: TimeInterval = 0
        for (index, item) in ordered.enumerated() {
            let nextDate: Date
            if index + 1 < ordered.count {
                nextDate = ordered[index + 1].createdAt
            } else {
                nextDate = min(now, item.createdAt.addingTimeInterval(8 * 60))
            }

            let delta = max(0, nextDate.timeIntervalSince(item.createdAt))
            total += min(delta, 30 * 60)
        }
        return total
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

    private static func relationalAnswer(query: String, candidates: [MemoryItem]) -> MemoryLaneAnswer? {
        let before = query.contains("before")
        let after = query.contains("after")
        guard before || after else { return nil }

        let relationshipToken = before ? "before" : "after"
        let pieces = query.components(separatedBy: relationshipToken)
        let leftText = pieces.first ?? ""
        let rightText = pieces.dropFirst().joined(separator: relationshipToken)

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

    private static func answerSummary(query: String, items: [MemoryItem]) -> String {
        guard !items.isEmpty else {
            return "I couldn't find a strong match in the local timeline for “\(query)”. Try an app name, project/file name, or a time such as “around 10:30 AM.”"
        }

        let apps = orderedUnique(items.map(.sourceApp))
        let appPhrase = naturalList(Array(apps.prefix(3)))
        let ordered = items.sorted { $0.createdAt < $1.createdAt }

        guard let first = ordered.first, let last = ordered.last else {
            return "I found matching activity in your local timeline."
        }

        let timeRange: String
        if Calendar.current.isDate(first.createdAt, inSameDayAs: last.createdAt) {
            timeRange = "\(first.createdAt.formatted(date: .omitted, time: .shortened))–\(last.createdAt.formatted(date: .omitted, time: .shortened))"
        } else {
            timeRange = "\(first.createdAt.formatted(date: .abbreviated, time: .shortened)) through \(last.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }

        if appPhrase.isEmpty {
            return "I found \(items.count) relevant activit\(items.count == 1 ? "y" : "ies") around \(timeRange)."
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
