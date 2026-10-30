import AppKit
import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    @State private var query = ""
    @State private var answer: MemoryLaneAnswer?
    @FocusState private var searchFocused: Bool

    private let examples = [
        "What was I doing around 10:30 AM?",
        "What did I view before opening Teams?",
        "Show my activity from today",
        "Find a file I worked on yesterday"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                askBox

                if let answer {
                    answerCard(answer)

                    if !answer.items.isEmpty {
                        activityResults(answer.items)
                    }
                } else {
                    emptyState
                }
            }
            .padding(24)
        }
        .navigationTitle("")
        .onAppear {
            if query.isEmpty {
                searchFocused = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)

                Text("Ask Memory Lane")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            Text("Ask about a time, app, page, email, chat, file, or project. Answers are generated locally from your captured timeline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var askBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("What do you want to remember?", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($searchFocused)
                    .onSubmit(runQuery)

                if !query.isEmpty {
                    Button {
                        query = ""
                        answer = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: runQuery) {
                    Label("Ask", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button {
                            query = example
                            runQuery()
                        } label: {
                            Text(example)
                                .font(.caption)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 78, height: 78)
                .shadow(radius: 10, y: 5)

            VStack(spacing: 8) {
                Text("Your workday is searchable")
                    .font(.system(size: 27, weight: .semibold, design: .rounded))

                Text("Memory Lane can reason over captured timestamps, application names, window titles, URLs, filenames, and local file paths without sending your history to a cloud service.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            HStack(spacing: 14) {
                feature("clock", "Time-aware")
                feature("app.badge", "App-aware")
                feature("doc.text.magnifyingglass", "File-aware")
                feature("lock.shield", "Local")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func answerCard(_ answer: MemoryLaneAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory Lane found")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(answer.summary)
                        .font(.system(size: 16, weight: .medium))
                        .textSelection(.enabled)

                    if !answer.interpretedQuery.isEmpty {
                        Text(answer.interpretedQuery)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }

    private func activityResults(_ items: [MemoryItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("Supporting Activity")
                .font(.headline)

            ForEach(items) { item in
                NavigationLink {
                    MemoryDetailView(item: item)
                } label: {
                    MemoryRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func runQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            answer = nil
            return
        }

        answer = SearchService.ask(trimmed, memories: memories)
    }
}
