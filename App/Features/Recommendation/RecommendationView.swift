import SwiftUI
import Foundation
import DecideCore

/// The answer first. Everything that explains it lives behind "See analysis".
struct RecommendationView: View {
    let result: DecisionResult
    var chosenOptionID: String?
    let onChoose: (String) -> Void
    let onDone: () -> Void

    @State private var showingOtherOptions = false

    private var hasChosen: Bool { chosenOptionID != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DecideSpacing.l) {
                if hasChosen, let chosenID = chosenOptionID {
                    ChoiceConfirmation(result: result, chosenOptionID: chosenID)
                } else if result.strength == .unclear && result.ranking.count > 1 {
                    NoClearWinnerSection(result: result, onChoose: onChoose)
                } else if let recommended = result.recommendedOption {
                    recommendation(for: recommended)
                } else {
                    EmptyStateView(
                        title: "I couldn't land on a recommendation.",
                        message: "There wasn't enough here for me to stand behind one.",
                        systemImage: "questionmark.circle"
                    )
                }

                NavigationLink {
                    AnalysisView(result: result)
                } label: {
                    HStack {
                        Text("See analysis")
                            .font(DecideFont.callout.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(DecideColor.accent)
                    .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
                }
                .accessibilityHint("Criteria, comparison, assumptions, risks and sources")
            }
            .screenPadding()
            .padding(.top, DecideSpacing.m)
            .padding(.bottom, DecideSpacing.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            bottomAction
        }
        .sheet(isPresented: $showingOtherOptions) {
            OtherOptionsSheet(result: result) { optionID in
                showingOtherOptions = false
                onChoose(optionID)
            }
        }
    }

    @ViewBuilder
    private var bottomAction: some View {
        VStack(spacing: DecideSpacing.s) {
            if hasChosen {
                PrimaryButton(title: "Done", action: onDone)
            } else if let recommended = result.recommendedOption, result.strength != .unclear {
                // Never "accept". The user is not approving DECIDE's decision.
                PrimaryButton(title: "Make my decision") {
                    onChoose(recommended.id)
                }
                if result.ranking.count > 1 {
                    Button("Choose something else") { showingOtherOptions = true }
                        .font(DecideFont.footnote)
                        .frame(minHeight: DecideSpacing.minimumTouchTarget)
                }
            }
        }
        .screenPadding()
        .padding(.vertical, DecideSpacing.s)
        .background(.bar)
    }

    @ViewBuilder
    private func recommendation(for option: DecisionOption) -> some View {
        VStack(alignment: .leading, spacing: DecideSpacing.l) {
            VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                Text("MY RECOMMENDATION")
                    .font(DecideFont.monoLabel)
                    .foregroundStyle(DecideColor.tertiaryText)
                    .accessibilityHidden(true)
                Text(option.name)
                    .font(DecideFont.display)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.headline.isEmpty ? "Best fit for you" : result.headline)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("My recommendation: \(option.name). \(result.headline)")

            if !result.reasons.isEmpty {
                VStack(alignment: .leading, spacing: DecideSpacing.m) {
                    SectionHeader(title: "Why it fits you")
                    ForEach(Array(result.reasons.prefix(3).enumerated()), id: \.element.id) { index, reason in
                        NumberedRow(index: index + 1, title: reason.title, detail: reason.detail)
                    }
                }
            }

            if let tradeOff = result.tradeOffs.first {
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                        Text("The trade-off")
                            .font(DecideFont.footnote.weight(.medium))
                            .foregroundStyle(DecideColor.tertiaryText)
                        Text("You're giving up \(tradeOff.givingUp.lowercasedFirst) to get \(tradeOff.gaining.lowercasedFirst).")
                            .font(DecideFont.callout)
                            .foregroundStyle(DecideColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    Text("Decision strength")
                        .font(DecideFont.footnote.weight(.medium))
                        .foregroundStyle(DecideColor.tertiaryText)
                    StrengthBadge(strength: result.strength, showsExplanation: true)
                }
            }

            if let challenge = result.challenge {
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.s) {
                        Text("What could make me wrong?")
                            .font(DecideFont.footnote.weight(.medium))
                            .foregroundStyle(DecideColor.tertiaryText)
                        Text(challenge.strongestCaseAgainst)
                            .font(DecideFont.callout)
                            .foregroundStyle(DecideColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if result.unverifiedResearch {
                InlineNotice(
                    text: "I couldn't verify some of the information I used. The analysis shows what I checked.",
                    kind: .warning
                )
            }
        }
    }
}

// MARK: - No clear winner

private struct NoClearWinnerSection: View {
    let result: DecisionResult
    let onChoose: (String) -> Void

    @State private var showingConditionalPick = false

    private var topTwo: [DecisionOption] {
        result.ranking.prefix(2).compactMap { scored in
            result.options.first { $0.id == scored.optionID }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.l) {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text("There isn't a clear winner")
                    .font(DecideFont.display)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each of these is better at something different, and neither stays ahead when your priorities shift.")
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            ForEach(topTwo) { option in
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.s) {
                        Text(option.name)
                            .font(DecideFont.headline)
                            .foregroundStyle(DecideColor.primaryText)
                        if let strengths = bestCriteria(for: option), !strengths.isEmpty {
                            Text("Choose it if \(strengths) matters most.")
                                .font(DecideFont.callout)
                                .foregroundStyle(DecideColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        SecondaryButton(title: "Choose \(option.name)") { onChoose(option.id) }
                    }
                }
            }

            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    StrengthBadge(strength: .unclear, showsExplanation: true)
                    if let leading = result.recommendedOption {
                        if showingConditionalPick {
                            Text("If you want me to break the tie: \(leading.name), by a margin small enough that I wouldn't defend it.")
                                .font(DecideFont.callout)
                                .foregroundStyle(DecideColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            SecondaryButton(title: "Choose \(leading.name)") { onChoose(leading.id) }
                        } else {
                            Button("Choose for me anyway") { showingConditionalPick = true }
                                .font(DecideFont.footnote)
                                .frame(minHeight: DecideSpacing.minimumTouchTarget)
                        }
                    }
                }
            }
        }
    }

    /// The criteria this option is genuinely better at than the alternative.
    private func bestCriteria(for option: DecisionOption) -> String? {
        guard let other = topTwo.first(where: { $0.id != option.id }) else { return nil }
        let names = result.criteria
            .filter { option.score(for: $0.id) - other.score(for: $0.id) > 0.1 }
            .sorted { $0.weight > $1.weight }
            .prefix(2)
            .map { $0.name.lowercased() }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " and ")
    }
}

// MARK: - Choosing something else

private struct OtherOptionsSheet: View {
    let result: DecisionResult
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DecideSpacing.s) {
                    ForEach(result.ranking) { scored in
                        Button {
                            onChoose(scored.optionID)
                        } label: {
                            DecideCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                                        Text(scored.name)
                                            .font(DecideFont.callout.weight(.semibold))
                                            .foregroundStyle(DecideColor.primaryText)
                                        if scored.optionID == result.recommendedOptionID {
                                            Text("My recommendation")
                                                .font(DecideFont.caption)
                                                .foregroundStyle(DecideColor.secondaryText)
                                        }
                                    }
                                    Spacer(minLength: DecideSpacing.s)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(DecideColor.tertiaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !result.eliminated.isEmpty {
                        VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                            Text("Ruled out by your requirements")
                                .font(DecideFont.footnote.weight(.medium))
                                .foregroundStyle(DecideColor.tertiaryText)
                            ForEach(result.eliminated) { option in
                                Text("\(option.name) — \(option.failedConstraints.joined(separator: ", "))")
                                    .font(DecideFont.footnote)
                                    .foregroundStyle(DecideColor.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DecideSpacing.m)
                    }
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.m)
            }
            .background(DecideColor.background)
            .navigationTitle("Your options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - After the choice

/// No arguing, no "are you sure?". What they gain, what they give up, and it's theirs.
private struct ChoiceConfirmation: View {
    let result: DecisionResult
    let chosenOptionID: String

    private var chosen: DecisionOption? { result.option(withID: chosenOptionID) }
    private var alternative: DecisionOption? {
        guard let recommended = result.recommendedOptionID, recommended != chosenOptionID else {
            return result.ranking.first { $0.optionID != chosenOptionID }
                .flatMap { scored in result.options.first { $0.id == scored.optionID } }
        }
        return result.option(withID: recommended)
    }

    private var gaining: [String] {
        guard let chosen, let alternative else { return [] }
        return result.criteria
            .filter { chosen.score(for: $0.id) - alternative.score(for: $0.id) > 0.1 }
            .sorted { $0.weight > $1.weight }
            .prefix(3)
            .map(\.name)
    }

    private var givingUp: [String] {
        guard let chosen, let alternative else { return [] }
        return result.criteria
            .filter { alternative.score(for: $0.id) - chosen.score(for: $0.id) > 0.1 }
            .sorted { $0.weight > $1.weight }
            .prefix(3)
            .map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.l) {
            VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                Text("You chose")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)
                Text(chosen?.name ?? "your option")
                    .font(DecideFont.display)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if !gaining.isEmpty {
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                        Text("You're gaining")
                            .font(DecideFont.footnote.weight(.medium))
                            .foregroundStyle(DecideColor.tertiaryText)
                        ForEach(gaining, id: \.self) { item in
                            Text("• \(item)")
                                .font(DecideFont.callout)
                                .foregroundStyle(DecideColor.primaryText)
                        }
                    }
                }
            }

            if !givingUp.isEmpty {
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                        Text("You're giving up")
                            .font(DecideFont.footnote.weight(.medium))
                            .foregroundStyle(DecideColor.tertiaryText)
                        ForEach(givingUp, id: \.self) { item in
                            Text("• \(item)")
                                .font(DecideFont.callout)
                                .foregroundStyle(DecideColor.primaryText)
                        }
                    }
                }
            }

            Text("Your choice is yours.")
                .font(DecideFont.callout)
                .foregroundStyle(DecideColor.secondaryText)
        }
    }
}

extension String {
    /// Lowercases only the first character, so a sentence can embed a label
    /// without shouting mid-sentence.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
