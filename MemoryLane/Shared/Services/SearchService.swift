import Foundation

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
        "application", "focused", "window", "page", "item", "activity", "opened",
        "email", "emails", "message", "messages", "subject", "about", "regarding",
        "titled", "called", "containing", "contains", "read", "received", "sent",
        "lookup", "looking", "please"
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

        var candidates = memories.filter { !$0.isCaptureNoise }
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

        if let outlookAnswer = outlookEmailAnswerIfNeeded(
            query: trimmed,
            lowerQuery: lower,
            candidates: candidates,
            targetDay: targetDay,
            appFilter: appFilter
        ) {
            return outlookAnswer
        }

        let queryTokens = meaningfulTokens(for: trimmed)
        let ranked = candidates
            .map { item -> (MemoryItem, Int) in
                let text = item.searchableText
                var score = 0
                for token in queryTokens {
                    if text.localizedStandardContains(token) { score += 20 }
                    if item.displayTitle.lowercased().localizedStandardContains(token) { score += 15 }
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
            .map { $0.0 }

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

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private struct OutlookQueryIntent {
        let senderTerms: [String]
        let subjectTerms: [String]
        let freeTerms: [String]
        let exactPhrases: [String]

        var hasStructuredTerms: Bool {
            !senderTerms.isEmpty || !subjectTerms.isEmpty || !exactPhrases.isEmpty
        }
    }

    private struct OutlookRankedItem {
        let item: MemoryItem
        let score: Int
        let strictMatch: Bool
    }

    private static let outlookIntentNoise: Set<String> = [
        "a", "an", "and", "are", "at", "about", "before", "after", "called",
        "containing", "contains", "did", "do", "email", "emails", "find", "for",
        "from", "i", "in", "is", "it", "looking", "lookup", "mail", "me", "message",
        "messages", "microsoft", "my", "of", "on", "opened", "outlook", "please",
        "read", "received", "regarding", "sent", "show", "subject", "the", "this",
        "titled", "to", "today", "view", "viewed", "was", "were", "what", "when",
        "where", "with", "yesterday", "around", "am", "pm", "line"
    ]

    private static func outlookEmailAnswerIfNeeded(
        query: String,
        lowerQuery: String,
        candidates: [MemoryItem],
        targetDay: Date?,
        appFilter: DetectedApp?
    ) -> MemoryLaneAnswer? {
        let queryTokenSet = Set(tokens(for: lowerQuery))
        let explicitOutlook = appFilter?.displayName == "Outlook"
        let asksForEmail = queryTokenSet.contains("email") || queryTokenSet.contains("emails")
        let hasOutlookHistory = candidates.contains(where: isOutlookMemory)

        guard explicitOutlook || (appFilter == nil && asksForEmail && hasOutlookHistory) else {
            return nil
        }

        let outlookItems = candidates.filter(isOutlookMemory)
        let intent = outlookIntent(for: lowerQuery)

        let ranked = outlookItems.map { item -> OutlookRankedItem in
            let subject = item.displayTitle.lowercased()
            let sender = outlookSenderText(item).lowercased()
            let searchable = item.searchableText

            var score = 0
            var senderMatches = 0
            var subjectMatches = 0
            var freeMatches = 0

            for phrase in intent.exactPhrases {
                if text(subject, matches: phrase) {
                    score += 140
                } else if text(sender, matches: phrase) {
                    score += 110
                } else if text(searchable, matches: phrase) {
                    score += 70
                }
            }

            for term in intent.senderTerms {
                if text(sender, matches: term) {
                    senderMatches += 1
                    score += 75
                } else if text(searchable, matches: term) {
                    score += 18
                }
            }

            for term in intent.subjectTerms {
                if text(subject, matches: term) {
                    subjectMatches += 1
                    score += 60
                } else if text(searchable, matches: term) {
                    score += 15
                }
            }

            for term in intent.freeTerms {
                if text(subject, matches: term) {
                    freeMatches += 1
                    score += 38
                } else if text(sender, matches: term) {
                    freeMatches += 1
                    score += 30
                } else if text(searchable, matches: term) {
                    freeMatches += 1
                    score += 16
                }
            }

            if !intent.senderTerms.isEmpty && senderMatches == intent.senderTerms.count {
                score += 120
            }

            if !intent.subjectTerms.isEmpty && subjectMatches == intent.subjectTerms.count {
                score += 100
            }

            if !intent.freeTerms.isEmpty && freeMatches == intent.freeTerms.count {
                score += 45
            }

            if intent.senderTerms.isEmpty &&
                intent.subjectTerms.isEmpty &&
                intent.freeTerms.isEmpty &&
                intent.exactPhrases.isEmpty {
                score = 10
            }

            if item.isFavorite {
                score += 3
            }

            let senderStrict = intent.senderTerms.isEmpty || senderMatches == intent.senderTerms.count
            let subjectStrict = intent.subjectTerms.isEmpty || subjectMatches == intent.subjectTerms.count
            let freeStrict = intent.freeTerms.isEmpty || freeMatches > 0
            let phraseStrict = intent.exactPhrases.isEmpty || intent.exactPhrases.contains {
                text(subject, matches: $0) || text(sender, matches: $0)
            }

            return OutlookRankedItem(
                item: item,
                score: score,
                strictMatch: senderStrict && subjectStrict && freeStrict && phraseStrict
            )
        }
        .filter { $0.score > 0 }
        .sorted {
            if $0.score == $1.score {
                return $0.item.createdAt > $1.item.createdAt
            }
            return $0.score > $1.score
        }

        let strict = ranked.filter { $0.strictMatch }
        let selected = strict.isEmpty ? ranked : strict
        let results = Array(selected.prefix(12).map { $0.item })

        return MemoryLaneAnswer(
            summary: outlookAnswerSummary(query: query, items: results),
            items: results,
            interpretedQuery: outlookInterpretation(
                intent: intent,
                targetDay: targetDay
            )
        )
    }

    private static func outlookIntent(for lowerQuery: String) -> OutlookQueryIntent {
        let senderPhrase = captureFirstGroup(
            pattern: #"(?:^|\s)from\s+(.+?)(?=\s+(?:about|regarding|subject|titled|called|today|yesterday|around|before|after)\b|$)"#,
            in: lowerQuery
        )

        let subjectPhrase = captureFirstGroup(
            pattern: #"(?:about|regarding|titled|called|subject(?:\s+line)?(?:\s+(?:is|contains|containing))?)\s+(.+?)(?=\s+(?:from|today|yesterday|around|before|after)\b|$)"#,
            in: lowerQuery
        )

        let senderTerms = intentTerms(from: senderPhrase ?? "")
        let subjectTerms = intentTerms(from: subjectPhrase ?? "")
        let structuredTerms = Set(senderTerms + subjectTerms)

        let freeTerms = meaningfulTokens(for: lowerQuery)
            .filter { !structuredTerms.contains($0) }

        return OutlookQueryIntent(
            senderTerms: orderedUnique(senderTerms),
            subjectTerms: orderedUnique(subjectTerms),
            freeTerms: orderedUnique(freeTerms),
            exactPhrases: quotedPhrases(in: lowerQuery)
        )
    }

    private static func intentTerms(from value: String) -> [String] {
        tokens(for: value).filter { token in
            token.count > 1 &&
            Int(token) == nil &&
            !outlookIntentNoise.contains(token)
        }
    }

    private static func quotedPhrases(in query: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[\"“]([^\"”]{2,})[\"”]"#) else {
            return []
        }

        let ns = query as NSString
        return regex.matches(in: query, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else {
                return nil
            }

            return ns.substring(with: match.range(at: 1))
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func captureFirstGroup(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let ns = value as NSString
        guard let match = regex.firstMatch(
            in: value,
            range: NSRange(location: 0, length: ns.length)
        ),
        match.numberOfRanges > 1,
        match.range(at: 1).location != NSNotFound
        else {
            return nil
        }

        return ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func text(_ haystack: String, matches term: String) -> Bool {
        let normalizedTerm = term
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTerm.isEmpty else { return false }

        let lowerHaystack = haystack.lowercased()
        if lowerHaystack.localizedStandardContains(normalizedTerm) {
            return true
        }

        guard normalizedTerm.count >= 4 else { return false }

        return tokens(for: lowerHaystack).contains { token in
            token.hasPrefix(normalizedTerm) ||
            (token.count >= 4 && normalizedTerm.hasPrefix(token))
        }
    }

    private static func isOutlookMemory(_ item: MemoryItem) -> Bool {
        item.sourceBundleID.lowercased() == "com.microsoft.outlook" ||
            item.sourceApp.lowercased().contains("outlook")
    }

    private static func outlookSenderText(_ item: MemoryItem) -> String {
        let body = item.body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if body.lowercased().hasPrefix("from:") {
            return String(body.dropFirst("from:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return body
    }

    private static func outlookAnswerSummary(query: String, items: [MemoryItem]) -> String {
        guard let best = items.first else {
            return "I couldn't find an Outlook email matching “\(query)”. Try part of the sender's name, a few words from the subject, or a day such as today or yesterday."
        }

        let sender = outlookSenderText(best)
        let senderPhrase = sender.isEmpty ? "" : " from \(sender)"
        let time = best.createdAt.formatted(date: .abbreviated, time: .shortened)

        if items.count == 1 {
            return "Best Outlook match: “\(best.displayTitle)”\(senderPhrase), viewed \(time)."
        }

        return "I found \(items.count) Outlook email matches. Best match: “\(best.displayTitle)”\(senderPhrase), viewed \(time)."
    }

    private static func outlookInterpretation(
        intent: OutlookQueryIntent,
        targetDay: Date?
    ) -> String {
        var parts = ["Outlook email"]

        if let targetDay {
            parts.append(targetDay.formatted(date: .abbreviated, time: .omitted))
        }

        if !intent.senderTerms.isEmpty {
            parts.append("sender: " + intent.senderTerms.joined(separator: " "))
        }

        if !intent.subjectTerms.isEmpty {
            parts.append("subject: " + intent.subjectTerms.joined(separator: " "))
        }

        if !intent.freeTerms.isEmpty {
            parts.append(intent.freeTerms.prefix(4).joined(separator: ", "))
        }

        return parts.joined(separator: " · ")
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

        let queryTokens = Set(tokens(for: query))
        for (name, aliases) in map where aliases.contains(where: { queryTokens.contains($0) }) {
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
            summary = "Immediately \(relationship) the \(targetApp.displayName) activity at \(target.createdAt.formatted(date: .omitted, time: .shortened)), Memory Lane found \(nearest.sourceApp): “\(nearest.displayTitle)”."
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

        let apps = orderedUnique(items.map { $0.sourceApp })
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
