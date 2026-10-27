import Foundation

enum SearchService {
    static func tokens(for query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func matches(_ item: MemoryItem, query: String) -> Bool {
        matches(item, tokens: tokens(for: query))
    }

    static func matches(_ item: MemoryItem, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let haystack = item.searchableText
        return tokens.allSatisfy { haystack.localizedStandardContains($0) }
    }
}
