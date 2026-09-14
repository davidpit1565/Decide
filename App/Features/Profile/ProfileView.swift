import SwiftUI
import DecideCore
import DecideFlow

/// What DECIDE knows, and how to make it forget. No account, no profile to fill in.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingPaywall = false
    @State private var confirmation: DataConfirmation?

    private enum DataConfirmation: String, Identifiable {
        case memory
        case decisions
        case outcomes
        case everything

        var id: String { rawValue }

        var title: String {
            switch self {
            case .memory: return "Delete all Decision Memory?"
            case .decisions: return "Delete all decisions?"
            case .outcomes: return "Delete all outcomes?"
            case .everything: return "Delete everything?"
            }
        }

        var message: String {
            switch self {
            case .memory: return "Every preference DECIDE has learned is removed. Your decisions stay."
            case .decisions: return "Every saved decision and its analysis is removed. This can't be undone."
            case .outcomes: return "Every 'how did it go' answer is removed. Your decisions stay."
            case .everything: return "Decisions, memory and outcomes are all removed from this device. This can't be undone."
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DecideSpacing.xl) {
                    subscriptionSection
                    memorySection
                    dataSection
                    aboutSection
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.m)
            }
            .background(DecideColor.background)
            .navigationTitle("Profile")
            .sheet(isPresented: $showingPaywall) {
                PaywallView(context: .profile)
            }
            .alert(
                confirmation?.title ?? "",
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil } }
                ),
                presenting: confirmation
            ) { item in
                Button("Delete", role: .destructive) { perform(item) }
                Button("Keep", role: .cancel) {}
            } message: { item in
                Text(item.message)
            }
        }
    }

    // MARK: Sections

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            SectionHeader(title: "Your plan")
            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    switch environment.subscriptions.entitlement {
                    case .unknown, .checking:
                        HStack(spacing: DecideSpacing.s) {
                            ProgressView()
                            Text("Checking your subscription…")
                                .font(DecideFont.callout)
                                .foregroundStyle(DecideColor.secondaryText)
                        }
                    case .notSubscribed:
                        Text("Free")
                            .font(DecideFont.headline)
                            .foregroundStyle(DecideColor.primaryText)
                        Text("\(FeatureAccess.freeDeepDecisionsPerMonth) deep decisions a month, and your last \(FeatureAccess.freeHistoryLimit) decisions.")
                            .font(DecideFont.footnote)
                            .foregroundStyle(DecideColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        SecondaryButton(title: "See Pro") { showingPaywall = true }
                    case .subscribed(let expires, let isInGracePeriod):
                        Text("Pro")
                            .font(DecideFont.headline)
                            .foregroundStyle(DecideColor.primaryText)
                        if isInGracePeriod {
                            Text("There's a problem with your billing. Access continues while Apple retries.")
                                .font(DecideFont.footnote)
                                .foregroundStyle(DecideColor.moderate)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let expires {
                            Text("Renews \(expires.formatted(.dateTime.month(.abbreviated).day().year()))")
                                .font(DecideFont.footnote)
                                .foregroundStyle(DecideColor.secondaryText)
                        }
                    case .billingRetry(let expires):
                        Text("Pro — billing issue")
                            .font(DecideFont.headline)
                            .foregroundStyle(DecideColor.primaryText)
                        Text("Apple couldn't take the payment\(expires.map { ". Access continues until \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? ""). You can fix this in your Apple Account settings.")
                            .font(DecideFont.footnote)
                            .foregroundStyle(DecideColor.moderate)
                            .fixedSize(horizontal: false, vertical: true)
                    case .expired(let date):
                        Text("Pro has ended")
                            .font(DecideFont.headline)
                            .foregroundStyle(DecideColor.primaryText)
                        if let date {
                            Text("Ended \(date.formatted(.dateTime.month(.abbreviated).day().year())). Your decisions are still here.")
                                .font(DecideFont.footnote)
                                .foregroundStyle(DecideColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        SecondaryButton(title: "See Pro") { showingPaywall = true }
                    }

                    if environment.subscriptions.entitlement.isResolved {
                        Button("Restore purchases") {
                            Task { _ = await environment.subscriptions.restorePurchases() }
                        }
                        .font(DecideFont.footnote)
                        .frame(minHeight: DecideSpacing.minimumTouchTarget)
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            SectionHeader(
                title: "Decision Memory",
                subtitle: "Preferences DECIDE noticed in decisions you actually made. Nothing is stored without your say-so."
            )

            if !environment.isPro {
                DecideCard {
                    VStack(alignment: .leading, spacing: DecideSpacing.s) {
                        Text("Decision Memory is part of Pro.")
                            .font(DecideFont.callout)
                            .foregroundStyle(DecideColor.primaryText)
                        SecondaryButton(title: "See Pro") { showingPaywall = true }
                    }
                }
            } else if environment.memory.isEmpty {
                EmptyStateView(
                    title: "Nothing learned yet.",
                    message: "After a few decisions, DECIDE may notice a pattern and ask whether to remember it.",
                    systemImage: "brain"
                )
            } else {
                VStack(spacing: DecideSpacing.s) {
                    ForEach(environment.memory) { entry in
                        MemoryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            SectionHeader(
                title: "Your data",
                subtitle: "Everything is stored on this device. Decisions, memory and outcomes are kept separately, and can be deleted separately."
            )
            DecideCard {
                VStack(alignment: .leading, spacing: 0) {
                    dataRow("Delete all Decision Memory", isEnabled: !environment.memory.isEmpty) {
                        confirmation = .memory
                    }
                    Divider().overlay(DecideColor.separator)
                    dataRow("Delete all outcomes", isEnabled: environment.decisions.contains { $0.outcome != nil }) {
                        confirmation = .outcomes
                    }
                    Divider().overlay(DecideColor.separator)
                    dataRow("Delete all decisions", isEnabled: !environment.decisions.isEmpty) {
                        confirmation = .decisions
                    }
                    Divider().overlay(DecideColor.separator)
                    dataRow("Delete everything", isEnabled: !environment.decisions.isEmpty || !environment.memory.isEmpty) {
                        confirmation = .everything
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            SectionHeader(title: "About")
            DecideCard {
                VStack(alignment: .leading, spacing: DecideSpacing.s) {
                    if let url = environment.configuration.privacyPolicyURL {
                        Link("Privacy Policy", destination: url)
                            .font(DecideFont.callout)
                            .frame(minHeight: DecideSpacing.minimumTouchTarget)
                    }
                    if let url = environment.configuration.termsURL {
                        Link("Terms of Use", destination: url)
                            .font(DecideFont.callout)
                            .frame(minHeight: DecideSpacing.minimumTouchTarget)
                    }
                    if let url = environment.configuration.supportURL {
                        Link("Support", destination: url)
                            .font(DecideFont.callout)
                            .frame(minHeight: DecideSpacing.minimumTouchTarget)
                    }
                    Text("DECIDE analyses decisions with the help of an AI model. It can be wrong, and it tells you how confident the analysis is rather than pretending to be certain. The final decision is always yours.")
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(DecideFont.caption)
                            .foregroundStyle(DecideColor.tertiaryText)
                    }
                }
            }
        }
    }

    private func dataRow(_ title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(DecideFont.callout)
                    .foregroundStyle(isEnabled ? DecideColor.unclear : DecideColor.tertiaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func perform(_ confirmation: DataConfirmation) {
        switch confirmation {
        case .memory: environment.deleteAllMemory()
        case .decisions: environment.deleteAllDecisions()
        case .outcomes: environment.deleteAllOutcomes()
        case .everything: environment.deleteEverything()
        }
    }
}

private struct MemoryRow: View {
    let entry: MemoryEntry
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        DecideCard {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text(entry.statement)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Noticed in \(entry.evidenceCount) of your decisions")
                    .font(DecideFont.caption)
                    .foregroundStyle(DecideColor.tertiaryText)

                HStack(spacing: DecideSpacing.m) {
                    Toggle(
                        "Use this",
                        isOn: Binding(
                            get: { entry.isEnabled },
                            set: { environment.setMemoryEnabled($0, for: entry) }
                        )
                    )
                    .font(DecideFont.footnote)
                    .toggleStyle(.switch)

                    Button("Remove", role: .destructive) {
                        environment.deleteMemory(entry)
                    }
                    .font(DecideFont.footnote)
                    .frame(minHeight: DecideSpacing.minimumTouchTarget)
                }
            }
        }
    }
}

/// Asked once, after a decision, and never assumed.
struct MemoryConsentSheet: View {
    let candidate: MemoryCandidate
    let onRemember: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.l) {
            VStack(alignment: .leading, spacing: DecideSpacing.s) {
                Text("I noticed something")
                    .font(DecideFont.footnote.weight(.medium))
                    .foregroundStyle(DecideColor.tertiaryText)
                Text(candidate.statement)
                    .font(DecideFont.title)
                    .foregroundStyle(DecideColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Want DECIDE to use this in future decisions? You can change or delete it at any time.")
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            PrimaryButton(title: "Remember", action: onRemember)
            Button("Not now", action: onDecline)
                .font(DecideFont.footnote)
                .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget)
        }
        .screenPadding()
        .padding(.vertical, DecideSpacing.l)
        .presentationDetents([.medium])
    }
}
