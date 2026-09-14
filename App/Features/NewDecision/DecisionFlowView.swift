import SwiftUI
import Foundation
import DecideCore
import DecideFlow

/// Runs one decision. Which screen the user sees is whatever the pipeline is
/// genuinely doing — there is no scripted sequence of animations.
struct DecisionFlowView: View {
    let prompt: String

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: DecisionCoordinator?
    @State private var showingMemoryConsent = false

    var body: some View {
        NavigationStack {
            Group {
                if let coordinator {
                    content(for: coordinator)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DecideColor.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        coordinator?.cancel()
                        dismiss()
                    }
                    .accessibilityLabel("Close this decision")
                }
            }
        }
        .task {
            guard coordinator == nil else { return }
            let new = environment.makeCoordinator()
            coordinator = new
            new.start(prompt: prompt)
        }
        // Asked once, after a decision is saved, and only ever with a yes/no.
        .sheet(isPresented: $showingMemoryConsent) {
            if let candidate = environment.pendingMemoryCandidate {
                MemoryConsentSheet(
                    candidate: candidate,
                    onRemember: {
                        environment.acceptPendingMemory()
                        showingMemoryConsent = false
                    },
                    onDecline: {
                        environment.declinePendingMemory()
                        showingMemoryConsent = false
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func content(for coordinator: DecisionCoordinator) -> some View {
        switch coordinator.phase {
        case .idle:
            ProgressView()

        case .working(let state):
            WorkingScreen(state: state, preliminary: coordinator.preliminary)

        case .asking(let question):
            QuestionScreen(
                question: question,
                preliminary: coordinator.preliminary,
                onAnswer: { coordinator.answer($0, to: question) },
                onSkip: { coordinator.skipQuestion(question) }
            )

        case .insufficient(let missing, let partial):
            InsufficientScreen(
                missing: missing,
                partial: partial,
                onChoose: { optionID in choose(optionID, with: coordinator) },
                onClose: { dismiss() }
            )

        case .finished(let result):
            RecommendationView(
                result: result,
                chosenOptionID: coordinator.chosenOptionID,
                onChoose: { optionID in choose(optionID, with: coordinator) },
                onDone: { dismiss() }
            )

        case .failed(let error):
            ErrorScreen(
                error: error,
                onRetry: { coordinator.retry() },
                onClose: { dismiss() }
            )
        }
    }

    private func choose(_ optionID: String, with coordinator: DecisionCoordinator) {
        guard let record = coordinator.makeChoice(optionID: optionID) else { return }
        environment.save(record)
        showingMemoryConsent = environment.pendingMemoryCandidate != nil
    }
}

// MARK: - Working

private struct WorkingScreen: View {
    let state: DecisionFlowState
    let preliminary: PreliminaryDirection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DecideSpacing.l) {
                WorkingStateView(
                    title: state.progressTitle ?? "Working",
                    subtitle: state.progressSubtitle
                )

                if let preliminary {
                    PreliminaryCard(direction: preliminary)
                }
            }
            .screenPadding()
            .padding(.top, DecideSpacing.xl)
        }
    }
}

/// Something useful within the first few seconds, before the analysis finishes.
private struct PreliminaryCard: View {
    let direction: PreliminaryDirection

    var body: some View {
        DecideCard {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text("I already have a direction")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)
                Text(direction.optionName)
                    .font(DecideFont.title)
                    .foregroundStyle(DecideColor.primaryText)
                Text(direction.rationale)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Before I finalize it…")
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Question

/// One question, presented as one question. No counter, no progress bar, no form.
private struct QuestionScreen: View {
    let question: QuestionCandidate
    let preliminary: PreliminaryDirection?
    let onAnswer: (String) -> Void
    let onSkip: () -> Void

    @State private var freeText = ""
    @State private var selectedChoices: Set<String> = []
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        switch question.kind {
        case .freeText:
            return !freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .singleChoice, .multipleChoice:
            return !selectedChoices.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DecideSpacing.l) {
                if let preliminary {
                    PreliminaryCard(direction: preliminary)
                }

                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    Text("One thing I need to know")
                        .font(DecideFont.footnote.weight(.medium))
                        .foregroundStyle(DecideColor.tertiaryText)
                    Text(question.text)
                        .font(DecideFont.title)
                        .foregroundStyle(DecideColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                answerControls
            }
            .screenPadding()
            .padding(.top, DecideSpacing.l)
            .padding(.bottom, DecideSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DecideSpacing.s) {
                PrimaryButton(
                    title: "Continue",
                    isEnabled: canSubmit,
                    identifier: DecideID.continueAfterQuestion
                ) {
                    isFocused = false
                    onAnswer(submissionValue)
                }
                Button("I'd rather not say") {
                    isFocused = false
                    onSkip()
                }
                .font(DecideFont.footnote)
                .frame(minHeight: DecideSpacing.minimumTouchTarget)
                .accessibilityHint("Continues without this answer, and DECIDE will say what it had to assume")
            }
            .screenPadding()
            .padding(.vertical, DecideSpacing.s)
            .background(.bar)
        }
    }

    private var submissionValue: String {
        switch question.kind {
        case .freeText:
            return freeText
        case .singleChoice, .multipleChoice:
            return selectedChoices.sorted().joined(separator: ", ")
        }
    }

    @ViewBuilder
    private var answerControls: some View {
        switch question.kind {
        case .freeText:
            TextField("Your answer", text: $freeText, axis: .vertical)
                .font(DecideFont.body)
                .lineLimit(2...6)
                .focused($isFocused)
                .padding(DecideSpacing.m)
                .background(DecideColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous)
                        .stroke(DecideColor.separator, lineWidth: 1)
                )

        case .singleChoice, .multipleChoice:
            VStack(spacing: DecideSpacing.s) {
                ForEach(question.choices, id: \.self) { choice in
                    ChoiceRow(
                        title: choice,
                        isSelected: selectedChoices.contains(choice),
                        allowsMultiple: question.kind == .multipleChoice
                    ) {
                        toggle(choice)
                    }
                }
            }
        }
    }

    private func toggle(_ choice: String) {
        if question.kind == .singleChoice {
            selectedChoices = [choice]
        } else if selectedChoices.contains(choice) {
            selectedChoices.remove(choice)
        } else {
            selectedChoices.insert(choice)
        }
    }
}

private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let allowsMultiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DecideSpacing.m) {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? DecideColor.accent : DecideColor.tertiaryText)
                Text(title)
                    .font(DecideFont.body)
                    .foregroundStyle(DecideColor.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
            .padding(.horizontal, DecideSpacing.m)
            .padding(.vertical, DecideSpacing.s)
            .background(DecideColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous)
                    .stroke(isSelected ? DecideColor.accent : DecideColor.separator, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var symbol: String {
        if allowsMultiple {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }
}

// MARK: - Not enough information

private struct InsufficientScreen: View {
    let missing: [String]
    let partial: DecisionResult?
    let onChoose: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DecideSpacing.l) {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    Text("I'm missing something important")
                        .font(DecideFont.title)
                        .foregroundStyle(DecideColor.primaryText)
                    Text("I could give you a guess, but I don't think that would be useful.")
                        .font(DecideFont.callout)
                        .foregroundStyle(DecideColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if !missing.isEmpty {
                    DecideCard {
                        VStack(alignment: .leading, spacing: DecideSpacing.s) {
                            Text("What I need")
                                .font(DecideFont.footnote.weight(.medium))
                                .foregroundStyle(DecideColor.tertiaryText)
                            ForEach(missing, id: \.self) { item in
                                Text("• \(item)")
                                    .font(DecideFont.callout)
                                    .foregroundStyle(DecideColor.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if let partial, let recommended = partial.recommendedOption {
                    DecideCard {
                        VStack(alignment: .leading, spacing: DecideSpacing.s) {
                            Text("Where I'd lean anyway")
                                .font(DecideFont.footnote.weight(.medium))
                                .foregroundStyle(DecideColor.tertiaryText)
                            Text(recommended.name)
                                .font(DecideFont.headline)
                                .foregroundStyle(DecideColor.primaryText)
                            StrengthBadge(strength: partial.strength, showsExplanation: true)
                            SecondaryButton(title: "Choose \(recommended.name) anyway") {
                                onChoose(recommended.id)
                            }
                        }
                    }
                }
            }
            .screenPadding()
            .padding(.top, DecideSpacing.l)
            .padding(.bottom, DecideSpacing.xxl)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Close", action: onClose)
                .screenPadding()
                .padding(.vertical, DecideSpacing.s)
                .background(.bar)
        }
    }
}

// MARK: - Errors

private struct ErrorScreen: View {
    let error: DecideServiceError
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.l) {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text(error.errorDescription ?? "Something went wrong")
                    .font(DecideFont.title)
                    .foregroundStyle(DecideColor.primaryText)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(DecideFont.callout)
                        .foregroundStyle(DecideColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if error.isRetryable {
                PrimaryButton(title: "Try again", identifier: DecideID.tryAgain, action: onRetry)
            }
            SecondaryButton(title: "Close", action: onClose)
            Spacer(minLength: 0)
        }
        .screenPadding()
        .padding(.top, DecideSpacing.xl)
    }
}
