import SwiftUI
import DecideCore
import DecideFlow

/// One question, one field, one button. The home screen is not a dashboard.
struct HomeView: View {
    var onSeeAllDecisions: () -> Void = {}

    @Environment(AppEnvironment.self) private var environment
    @State private var prompt = ""
    @State private var activeDecision: ActiveDecision?
    @State private var showingPaywall = false
    @State private var isConnected = true
    @FocusState private var isInputFocused: Bool

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canDecide: Bool { trimmedPrompt.count >= 3 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DecideSpacing.l) {
                    header
                    input
                    if !isInputFocused {
                        examples
                        recentDecisions
                    }
                }
                .screenPadding()
                .padding(.top, DecideSpacing.m)
                .padding(.bottom, DecideSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DecideColor.background)
            .navigationTitle("Decide")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                // The primary action stays within thumb reach and above the keyboard.
                PrimaryButton(title: "Decide", systemImage: "arrow.right", isEnabled: canDecide) {
                    startDecision()
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.s)
                .background(.bar)
            }
        }
        .task {
            // Reflects the connection as it changes, rather than whatever was true
            // when the screen was first drawn.
            for await connected in Reachability.shared.updates {
                isConnected = connected
            }
        }
        .fullScreenCover(item: $activeDecision) { active in
            DecisionFlowView(prompt: active.prompt)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .deepDecisionLimit)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            Text("What are you deciding?")
                .font(DecideFont.display)
                .foregroundStyle(DecideColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tell me what you're trying to figure out.")
                .font(DecideFont.callout)
                .foregroundStyle(DecideColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            TextField(
                "I'm deciding between…",
                text: $prompt,
                axis: .vertical
            )
            .font(DecideFont.body)
            .lineLimit(3...8)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($isInputFocused)
            .padding(DecideSpacing.m)
            .background(DecideColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous)
                    .stroke(isInputFocused ? DecideColor.accent : DecideColor.separator, lineWidth: 1)
            )
            .accessibilityLabel("What are you deciding?")

            if !isConnected {
                InlineNotice(
                    text: "You're offline. A new decision needs a connection — your saved decisions are still here.",
                    kind: .warning
                )
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            Text("For example")
                .font(DecideFont.footnote.weight(.medium))
                .foregroundStyle(DecideColor.tertiaryText)

            ForEach(Self.examplePrompts, id: \.self) { example in
                Button {
                    prompt = example
                    isInputFocused = true
                } label: {
                    HStack {
                        Text(example)
                            .font(DecideFont.callout)
                            .foregroundStyle(DecideColor.primaryText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: DecideSpacing.s)
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(DecideColor.tertiaryText)
                    }
                    .frame(minHeight: DecideSpacing.minimumTouchTarget)
                    .padding(.horizontal, DecideSpacing.m)
                    .background(DecideColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.s, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Uses this example as your decision")
            }
        }
    }

    @ViewBuilder
    private var recentDecisions: some View {
        let recent = Array(environment.visibleDecisions.prefix(3))

        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            HStack {
                Text("Recent decisions")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)
                Spacer()
                if !recent.isEmpty {
                    Button("See all", action: onSeeAllDecisions)
                        .font(DecideFont.footnote)
                        .frame(minHeight: DecideSpacing.minimumTouchTarget)
                }
            }

            if recent.isEmpty {
                EmptyStateView(
                    title: "Your decisions will appear here.",
                    message: nil,
                    systemImage: "square.stack.3d.up"
                )
            } else {
                ForEach(recent) { record in
                    NavigationLink {
                        DecisionDetailsView(record: record)
                    } label: {
                        DecisionRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startDecision() {
        isInputFocused = false
        let classification = DecisionClassifier.classify(trimmedPrompt)
        guard environment.canStartDecision(complexity: classification.complexity) else {
            environment.analytics.track(.paywallShown, properties: [.source: "deep_decision_limit"])
            showingPaywall = true
            return
        }
        activeDecision = ActiveDecision(prompt: trimmedPrompt)
    }

    static let examplePrompts = [
        "Which laptop should I buy?",
        "Should I take this job?",
        "Which apartment should I choose?",
        "Should I cancel this subscription?"
    ]
}

struct ActiveDecision: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
}

/// One line of history: what was decided, what was chosen, how strong it was.
struct DecisionRow: View {
    let record: DecisionRecord

    private var subtitle: String {
        let chosen = record.chosenOption?.name ?? record.result.recommendedOption?.name
        let strength = record.result.strength.title
        if let chosen {
            return "\(chosen) · \(strength)"
        }
        return "Not decided yet"
    }

    var body: some View {
        DecideCard {
            VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                Text(record.title)
                    .font(DecideFont.callout.weight(.semibold))
                    .foregroundStyle(DecideColor.primaryText)
                    .multilineTextAlignment(.leading)

                HStack(spacing: DecideSpacing.s) {
                    Text(subtitle)
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.secondaryText)
                    Spacer(minLength: DecideSpacing.s)
                    Text(record.createdAt.decideRelativeDescription)
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.tertiaryText)
                }

                if record.shouldReview {
                    Text("Things may have changed")
                        .font(DecideFont.caption)
                        .foregroundStyle(DecideColor.moderate)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title). \(subtitle). \(record.createdAt.decideRelativeDescription)")
    }
}

extension Date {
    var decideRelativeDescription: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: self, to: Date()).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        default:
            return formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
