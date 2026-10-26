import Foundation

enum SearchService {
    static func matches(_ item: MemoryItem, query: String) -> Bool {
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return true }
        let haystack = item.searchableText
        return tokens.allSatisfy { haystack.localizedStandardContains($0) }
    }
}
