import SwiftUI
import Foundation
import DecideCore

extension DecisionRecord {
    /// Research goes out of date. After a couple of months, a decision that leaned
    /// on current facts is worth a second look — without quietly rewriting it.
    var isPotentiallyStale: Bool {
        guard result.researchLevel != .none else { return false }
        return Date().timeIntervalSince(createdAt) > 60 * 60 * 24 * 60
    }

    var shouldReview: Bool { needsReview || isPotentiallyStale }

    /// Everything worth matching a search against.
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }

        let haystack = [
            title,
            prompt,
            result.understanding.restatement,
            result.category.rawValue.replacingOccurrences(of: "_", with: " ")
        ]
        + result.options.map(\.name)
        + result.criteria.map(\.name)

        return haystack.contains { $0.lowercased().contains(needle) }
    }
}

struct DecisionsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case needsReview = "Needs review"

        var id: String { rawValue }
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var filter: Filter = .all

    private var filtered: [DecisionRecord] {
        let base = environment.visibleDecisions.filter { $0.matches(query) }
        switch filter {
        case .all:
            return base
        case .recent:
            let cutoff = Date().addingTimeInterval(-60 * 60 * 24 * 30)
            return base.filter { $0.createdAt >= cutoff }
        case .needsReview:
            return base.filter(\.shouldReview)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if environment.decisions.isEmpty {
                    EmptyStateView(
                        title: "Your decisions will appear here.",
                        message: "Everything you decide is saved on this device.",
                        systemImage: "square.stack.3d.up"
                    )
                    .screenPadding()
                } else {
                    ScrollView {
                        VStack(spacing: DecideSpacing.s) {
                            Picker("Filter", selection: $filter) {
                                ForEach(Filter.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, DecideSpacing.xs)

                            if filtered.isEmpty {
                                EmptyStateView(
                                    title: "Nothing here",
                                    message: query.isEmpty
                                        ? "No decisions match this filter."
                                        : "No decisions match “\(query)”.",
                                    systemImage: "magnifyingglass"
                                )
                            } else {
                                ForEach(filtered) { record in
                                    NavigationLink {
                                        DecisionDetailsView(record: record)
                                    } label: {
                                        DecisionRow(record: record)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if environment.hasHiddenHistory {
                                HiddenHistoryNotice(hidden: environment.decisions.count - FeatureAccess.freeHistoryLimit)
                            }
                        }
                        .screenPadding()
                        .padding(.vertical, DecideSpacing.m)
                    }
                }
            }
            .background(DecideColor.background)
            .navigationTitle("Your decisions")
            .searchable(text: $query, prompt: "Search decisions")
        }
    }
}

private struct HiddenHistoryNotice: View {
    let hidden: Int
    @State private var showingPaywall = false

    var body: some View {
        DecideCard {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text("\(hidden) older \(hidden == 1 ? "decision is" : "decisions are") still saved on this device")
                    .font(DecideFont.callout.weight(.medium))
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pro shows your full history. Nothing has been deleted.")
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.secondaryText)
                SecondaryButton(title: "See Pro") { showingPaywall = true }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .history)
        }
    }
}
