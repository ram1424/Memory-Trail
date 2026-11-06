import AppKit
import SwiftUI
import SwiftData

struct SearchView: View {
    let memories: [MemoryItem]

    @State private var query = ""
    @State private var answer: MemoryTrailAnswer?
    @State private var selectedResult: MemoryItem?
    @FocusState private var searchFocused: Bool

#if APP_STORE_EDITION
    private let examples = [
        "What apps did I use earlier today?",
        "Show my activity from this week",
        "What was I doing around 10:30 AM?",
        "Show my most recent activity",
        "Find clipboard text from today",
        "What did I do before opening Outlook?",
        "What did I do after using Teams?",
        "Find a project or note I saved"
    ]
#else
    private let examples = [
        "What was I doing earlier today?",
        "Show my activity from this week",
        "Find files I worked on recently",
        "What emails did I view recently?",
        "What conversations did I have today?",
        "What websites did I visit?",
        "Show my most recent activity",
        "Find a project I worked on"
    ]
#endif

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                        .id("ask-memory-trail-top")

                    askBox

                    if let answer {
                        VStack(spacing: 16) {
                            answerCard(answer)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )

                            if !answer.items.isEmpty {
                                activityResults(answer.items)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }
                        }
                    } else {
                        quickStartDashboard
                    }
                }
                .padding(24)
            }
            .overlay(alignment: .bottomTrailing) {
                if answer != nil {
                    Button {
                        withAnimation(
                            .easeInOut(duration: 0.22)
                        ) {
                            proxy.scrollTo(
                                "ask-memory-trail-top",
                                anchor: .top
                            )
                        }
                    } label: {
                        Label(
                            "Back to Top",
                            systemImage: "arrow.up"
                        )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            .ultraThinMaterial,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    MemoryTrailPalette.border,
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: .black.opacity(0.10),
                            radius: 10,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Back to top")
                    .padding(.trailing, 28)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    MemoryTrailPalette.canvasTop,
                    MemoryTrailPalette.canvasBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("")
        .sheet(item: $selectedResult) { item in
            MemoryDetailView(item: item)
                .frame(minWidth: 760, minHeight: 650)
        }
        .onAppear {
            if query.isEmpty {
                searchFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.chat.filterTint)
                .frame(width: 48, height: 48)
                .background(
                    MemoryTrailCategory.chat.filterBackground,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Ask Memory Trails")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

#if APP_STORE_EDITION
                Text("Find the moments you remember — by time, app, copied text, note, or project.")
#else
                Text("Find the moments you remember — by time, app, page, email, chat, file, or project.")
#endif
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Label("Local Search", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MemoryTrailCategory.remoteAccess.filterTint)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    MemoryTrailCategory.remoteAccess.filterBackground,
                    in: Capsule()
                )
        }
    }

    private var askBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MemoryTrailCategory.allApps.filterTint)

                TextField("What do you want to remember?", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit(runQuery)

                if !query.isEmpty {
                    Button {
                        query = ""
                        answer = nil
                        selectedResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: runQuery) {
                    Label("Search", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .background(
                MemoryTrailPalette.elevatedStrong.opacity(0.97),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        MemoryTrailCategory.allApps.filterTint.opacity(0.14),
                        lineWidth: 1
                    )
            }

            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 235), spacing: 9)],
                spacing: 9
            ) {
                ForEach(Array(examples.prefix(6)), id: \.self) { example in
                    Button {
                        runQuery(example)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: promptSymbol(for: example))
                                .foregroundStyle(promptCategory(for: example).filterTint)

                            Text(example)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(
                            promptCategory(for: example).filterBackground.opacity(0.58),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private var quickStartDashboard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                searchCapabilityCard(
                    title: "Search your day",
                    detail: "Use natural phrases to find locally captured activity by time, app, text, note, file, or project.",
                    symbol: "clock.badge.questionmark",
                    category: .allApps
                )

                searchCapabilityCard(
                    title: "Local by design",
                    detail: "Queries run against your locally stored Memory Trails history. Your timeline is not sent to a cloud search service.",
                    symbol: "lock.shield.fill",
                    category: .remoteAccess
                )

                searchCapabilityCard(
                    title: "Open the trail",
                    detail: "Search results link back to captured activity so you can inspect the exact item and its context.",
                    symbol: "arrow.up.forward.app.fill",
                    category: .files
                )
            }

            VStack(spacing: 12) {
                searchCapabilityCard(
                    title: "Search your day",
                    detail: "Use natural phrases to find locally captured activity by time, app, text, note, file, or project.",
                    symbol: "clock.badge.questionmark",
                    category: .allApps
                )
                searchCapabilityCard(
                    title: "Local by design",
                    detail: "Queries run against your locally stored Memory Trails history. Your timeline is not sent to a cloud search service.",
                    symbol: "lock.shield.fill",
                    category: .remoteAccess
                )
                searchCapabilityCard(
                    title: "Open the trail",
                    detail: "Search results link back to captured activity so you can inspect the exact item and its context.",
                    symbol: "arrow.up.forward.app.fill",
                    category: .files
                )
            }
        }
    }

    private func searchCapabilityCard(
        title: String,
        detail: String,
        symbol: String,
        category: MemoryTrailCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(category.filterTint)
                .frame(width: 42, height: 42)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            category.filterBackground.opacity(0.38),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(category.filterTint.opacity(0.10), lineWidth: 1)
        }
    }

    private func promptCategory(for example: String) -> MemoryTrailCategory {
        let text = example.lowercased()
        if text.contains("email") || text.contains("conversation") { return .chat }
        if text.contains("file") || text.contains("project") { return .files }
        if text.contains("website") { return .web }
        return .allApps
    }

    private func promptSymbol(for example: String) -> String {
        let text = example.lowercased()

        if text.contains("email") {
            return "envelope.fill"
        }

        if text.contains("conversation") ||
            text.contains("chat") {
            return "bubble.left.and.bubble.right.fill"
        }

        if text.contains("website") ||
            text.contains("web") {
            return "globe"
        }

        if text.contains("file") {
            return "doc.text.fill"
        }

        if text.contains("project") {
            return "folder.fill"
        }

        if text.contains("week") {
            return "calendar"
        }

        if text.contains("recent") {
            return "clock.fill"
        }

        if text.contains("earlier") ||
            text.contains("today") {
            return "clock.arrow.circlepath"
        }

        return "sparkles"
    }

    private func answerCard(_ answer: MemoryTrailAnswer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Memory Trails found")
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
        .background(MemoryTrailCategory.chat.filterBackground.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MemoryTrailCategory.chat.filterTint.opacity(0.14), lineWidth: 1)
        }
    }

    private func activityResults(_ items: [MemoryItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Supporting Activity")
                    .font(.headline)

                Spacer(minLength: 0)

                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            ForEach(items) { item in
                Button {
                    selectedResult = item
                } label: {
                    HStack(spacing: 10) {
                        MemoryRow(item: item)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open activity details")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func runQuery() {
        runQuery(query)
    }

    private func runQuery(_ requestedQuery: String) {
        let trimmed = requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            answer = nil
            return
        }

        query = requestedQuery
        answer = SearchService.ask(trimmed, memories: memories)
    }
}
