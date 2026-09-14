import SwiftUI
import Foundation
import DecideCore

// MARK: - Buttons

/// The one primary action on a screen. Full width, thumb-reachable, never below 44pt.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    /// Stable handle for UI tests. Invisible to users, and needed because more
    /// than one control can legitimately carry the same visible label.
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DecideSpacing.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(DecideColor.onAccent)
                }
                Text(title)
                    .font(DecideFont.headline)
                if let systemImage, !isLoading {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget)
            .padding(.vertical, DecideSpacing.s)
            .foregroundStyle(DecideColor.onAccent)
            .background(DecideColor.accent.opacity(isEnabled && !isLoading ? 1 : 0.4))
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DecideSpacing.s) {
                Text(title).font(DecideFont.callout.weight(.medium))
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget)
            .foregroundStyle(DecideColor.accent)
            .background(DecideColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

// MARK: - Containers

struct DecideCard<Content: View>: View {
    var padding: CGFloat = DecideSpacing.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(DecideColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DecideSpacing.cornerRadius, style: .continuous)
                    .stroke(DecideColor.separator, lineWidth: 0.5)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.xs) {
            Text(title)
                .font(DecideFont.headline)
                .foregroundStyle(DecideColor.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Decision strength

/// Strength is communicated by shape, word and colour together — never colour alone.
struct StrengthBadge: View {
    let strength: DecisionStrength
    var showsExplanation: Bool = false

    private var colour: Color {
        switch strength {
        case .strong: return DecideColor.strong
        case .moderate: return DecideColor.moderate
        case .unclear: return DecideColor.unclear
        }
    }

    private var symbol: String {
        switch strength {
        case .strong: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .unclear: return "questionmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.xs) {
            HStack(spacing: DecideSpacing.s) {
                Image(systemName: symbol)
                    .font(.subheadline)
                Text(strength.title)
                    .font(DecideFont.subheadline.weight(.semibold))
            }
            .foregroundStyle(colour)

            if showsExplanation {
                Text(strength.explanation)
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Decision strength: \(strength.title). \(strength.explanation)")
    }
}

// MARK: - Numbered reasons

struct NumberedRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DecideSpacing.m) {
            Text(String(format: "%02d", index))
                .font(DecideFont.monoLabel)
                .foregroundStyle(DecideColor.tertiaryText)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DecideSpacing.xs) {
                Text(title)
                    .font(DecideFont.callout.weight(.semibold))
                    .foregroundStyle(DecideColor.primaryText)
                if !detail.isEmpty {
                    Text(detail)
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - States

struct EmptyStateView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: DecideSpacing.s) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(DecideColor.tertiaryText)
            Text(title)
                .font(DecideFont.callout.weight(.medium))
                .foregroundStyle(DecideColor.secondaryText)
            if let message {
                Text(message)
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DecideSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Reflects work that is actually happening. There is no decorative waiting in DECIDE.
struct WorkingStateView: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.m) {
            HStack(spacing: DecideSpacing.s) {
                ProgressView().progressViewStyle(.circular)
                Text(title)
                    .font(DecideFont.title)
                    .foregroundStyle(DecideColor.primaryText)
            }
            if let subtitle {
                Text(subtitle)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
    }
}

struct InlineNotice: View {
    enum Kind { case info, warning }

    let text: String
    var kind: Kind = .info

    private var symbol: String {
        switch kind {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DecideSpacing.s) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(kind == .warning ? DecideColor.moderate : DecideColor.secondaryText)
            Text(text)
                .font(DecideFont.footnote)
                .foregroundStyle(DecideColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DecideSpacing.s)
        .background(DecideColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: DecideSpacing.s, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Layout helpers

extension View {
    func screenPadding() -> some View {
        padding(.horizontal, DecideSpacing.screenMargin)
    }
}

/// Accessibility identifiers for the controls the UI tests drive.
///
/// These are identifiers, not labels: nothing here changes what a user sees or
/// hears. They exist because a visible label is not always unique — "Decide" is
/// both a tab and the primary action on the home screen.
enum DecideID {
    static let startDecision = "decide.start"
    static let decisionInput = "decide.input"
    static let makeDecision = "decide.make"
    static let chooseSomethingElse = "decide.chooseOther"
    static let continueAfterQuestion = "decide.question.continue"
    static let doneWithDecision = "decide.done"
    static let tryAgain = "decide.retry"
}
