import SwiftUI
import Foundation
import DecideCore

/// A decision from history: what was decided, what was chosen, how it went.
struct DecisionDetailsView: View {
    let record: DecisionRecord

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showingOutcome = false
    @State private var showingDeleteConfirmation = false
    @State private var newDecision: ActiveDecision?

    private var current: DecisionRecord {
        environment.decisions.first { $0.id == record.id } ?? record
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DecideSpacing.l) {
                summary
                whatYouToldMe
                outcomeSection

                NavigationLink {
                    AnalysisView(result: current.result)
                } label: {
                    HStack {
                        Text("See full analysis")
                            .font(DecideFont.callout.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(DecideColor.accent)
                    .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
                    // See the identical NavigationLink in RecommendationView for why
                    // this is needed: without it, only the narrow text + chevron is
                    // actually tappable, not the row it visually fills.
                    .contentShape(Rectangle())
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Text("Delete this decision")
                        .font(DecideFont.callout)
                        .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget)
                }
            }
            .screenPadding()
            .padding(.vertical, DecideSpacing.m)
        }
        .background(DecideColor.background)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this decision?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                environment.delete(current)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This removes the decision and everything stored with it. It can't be undone.")
        }
        .sheet(isPresented: $showingOutcome) {
            OutcomeSheet(record: current) { outcome in
                environment.recordOutcome(outcome, for: current)
                showingOutcome = false
            }
        }
        .fullScreenCover(item: $newDecision) { active in
            DecisionFlowView(prompt: active.prompt)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.m) {
            VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                Text(current.chosenOption != nil ? "You chose" : "I recommended")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)
                Text(current.chosenOption?.name ?? current.result.recommendedOption?.name ?? "No clear winner")
                    .font(DecideFont.title)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(current.createdAt.formatted(.dateTime.month(.wide).day().year()))
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.tertiaryText)
            }
            .accessibilityElement(children: .combine)

            DecideCard {
                StrengthBadge(strength: current.result.strength, showsExplanation: true)
            }

            if let followed = current.followedRecommendation, !followed,
               let recommended = current.result.recommendedOption {
                InlineNotice(text: "I had leaned towards \(recommended.name). You went another way — that's the point.")
            }
        }
    }

    /// What DECIDE understood, and the two ways to put it right. An old decision is
    /// never rewritten in place — both routes create a new one and leave this intact.
    private var whatYouToldMe: some View {
        DecideCard {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text("What you told me")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)

                Text(current.result.understanding.restatement)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !current.result.understanding.whatMatters.isEmpty {
                    Text(current.result.understanding.whatMatters.joined(separator: " · "))
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(DecideColor.separator)

                Text(
                    current.shouldReview
                        ? "Enough time has passed that the information behind this could be out of date."
                        : "Not quite right, or something has changed?"
                )
                .font(DecideFont.footnote)
                .foregroundStyle(current.shouldReview ? DecideColor.moderate : DecideColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                SecondaryButton(title: "Update this decision") {
                    newDecision = ActiveDecision(prompt: current.prompt)
                }
                Button("Start a different decision") { dismiss() }
                    .font(DecideFont.footnote)
                    .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget)
            }
        }
    }

    @ViewBuilder
    private var outcomeSection: some View {
        if let outcome = current.outcome {
            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                    Text("How it went")
                        .font(DecideFont.footnote.weight(.medium))
                        .foregroundStyle(DecideColor.tertiaryText)
                    Text(outcomeLabel(outcome.rating))
                        .font(DecideFont.callout.weight(.medium))
                        .foregroundStyle(DecideColor.primaryText)
                    if let note = outcome.note, !note.isEmpty {
                        Text(note)
                            .font(DecideFont.footnote)
                            .foregroundStyle(DecideColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if current.chosenOptionID != nil, current.isReadyForOutcome {
            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    Text("How did it go?")
                        .font(DecideFont.headline)
                        .foregroundStyle(DecideColor.primaryText)
                    SecondaryButton(title: "Tell me") { showingOutcome = true }
                }
            }
        }
    }

    private func outcomeLabel(_ rating: Outcome.Rating) -> String {
        switch rating {
        case .great: return "Great"
        case .mixed: return "Mixed"
        case .notGreat: return "Not great"
        }
    }
}

extension DecisionRecord {
    /// Asking "how did it go?" straight after a decision is noise. It only becomes
    /// a fair question once enough time has passed to have an answer.
    var isReadyForOutcome: Bool {
        guard let chosenAt else { return false }
        return Date().timeIntervalSince(chosenAt) > 60 * 60 * 24 * 7
    }
}

/// Never a pop-up after every decision: this is opened deliberately.
struct OutcomeSheet: View {
    let record: DecisionRecord
    let onSubmit: (Outcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Outcome.Rating?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DecideSpacing.l) {
                    Text("How did it go?")
                        .font(DecideFont.title)
                        .foregroundStyle(DecideColor.primaryText)

                    VStack(spacing: DecideSpacing.s) {
                        ratingButton(.great, title: "Great", symbol: "hand.thumbsup")
                        ratingButton(.mixed, title: "Mixed", symbol: "equal.circle")
                        ratingButton(.notGreat, title: "Not great", symbol: "hand.thumbsdown")
                    }

                    if rating == .notGreat || rating == .mixed {
                        VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                            Text("What went wrong? (optional)")
                                .font(DecideFont.footnote)
                                .foregroundStyle(DecideColor.secondaryText)
                            TextField("Optional", text: $note, axis: .vertical)
                                .font(DecideFont.body)
                                .lineLimit(2...5)
                                .padding(DecideSpacing.m)
                                .background(DecideColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
                        }
                    }
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DecideColor.background)
            .navigationTitle(record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save", isEnabled: rating != nil) {
                    guard let rating else { return }
                    onSubmit(Outcome(rating: rating, note: note.isEmpty ? nil : note))
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.s)
                .background(.bar)
            }
        }
    }

    private func ratingButton(_ value: Outcome.Rating, title: String, symbol: String) -> some View {
        Button {
            rating = value
        } label: {
            HStack(spacing: DecideSpacing.m) {
                Image(systemName: symbol)
                Text(title).font(DecideFont.body)
                Spacer()
                if rating == value {
                    Image(systemName: "checkmark").foregroundStyle(DecideColor.accent)
                }
            }
            .foregroundStyle(DecideColor.primaryText)
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
            .padding(.horizontal, DecideSpacing.m)
            .background(DecideColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous)
                    .stroke(rating == value ? DecideColor.accent : DecideColor.separator, lineWidth: rating == value ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(rating == value ? [.isButton, .isSelected] : .isButton)
    }
}
