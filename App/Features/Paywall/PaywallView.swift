import SwiftUI
import DecideFlow
import StoreKit

/// Shown only after DECIDE has already been useful. No countdowns, no invented
/// scarcity, no "1,000 AI messages" — the product is decision intelligence.
struct PaywallView: View {
    enum Context {
        case deepDecisionLimit
        case history
        case memory
        case profile

        var headline: String {
            "Make better decisions, with less effort."
        }

        var lead: String? {
            switch self {
            case .deepDecisionLimit:
                return "You've used your deep decisions for this month. Pro removes the cap."
            case .history:
                return "Pro shows your full decision history."
            case .memory:
                return "Decision Memory learns what you actually care about, with Pro."
            case .profile:
                return nil
            }
        }
    }

    let context: Context

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductID = SubscriptionService.ProductID.annual
    @State private var isPurchasing = false
    @State private var message: String?

    private var subscriptions: SubscriptionService { environment.subscriptions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DecideSpacing.l) {
                    header
                    benefits
                    plans
                    if let message {
                        InlineNotice(text: message, kind: .warning)
                    }
                    legal
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.m)
            }
            .background(DecideColor.background)
            .navigationTitle("DECIDE Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: DecideSpacing.s) {
                    PrimaryButton(
                        title: "Start Pro",
                        isLoading: isPurchasing,
                        isEnabled: selectedProduct != nil
                    ) {
                        purchase()
                    }
                    Button("Restore Purchases") { restore() }
                        .font(DecideFont.footnote)
                        .frame(minHeight: DecideSpacing.minimumTouchTarget)
                }
                .screenPadding()
                .padding(.vertical, DecideSpacing.s)
                .background(.bar)
            }
            .task {
                await subscriptions.loadProducts()
                environment.analytics.track(.paywallShown)
            }
            .onChange(of: subscriptions.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private var selectedProduct: Product? {
        subscriptions.products.first { $0.id == selectedProductID }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.s) {
            Text(context.headline)
                .font(DecideFont.display)
                .foregroundStyle(DecideColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let lead = context.lead {
                Text(lead)
                    .font(DecideFont.callout)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.m) {
            benefit("Deeper research", "More sources checked before a recommendation.")
            benefit("Advanced analysis", "Fuller comparisons, assumptions and risks.")
            benefit("Stress testing", "More variations run against every recommendation.")
            benefit("Decision Memory", "DECIDE remembers what you care about — only what you approve.")
            benefit("Outcome learning", "Tell DECIDE how it went, and it uses that next time.")
            benefit("Full history", "Every decision you've made, searchable.")
        }
    }

    private func benefit(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: DecideSpacing.m) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DecideColor.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DecideFont.callout.weight(.semibold))
                    .foregroundStyle(DecideColor.primaryText)
                Text(detail)
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var plans: some View {
        if subscriptions.isLoadingProducts {
            HStack(spacing: DecideSpacing.s) {
                ProgressView()
                Text("Loading plans…")
                    .font(DecideFont.footnote)
                    .foregroundStyle(DecideColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if subscriptions.products.isEmpty {
            InlineNotice(
                text: "I couldn't load the plans from the App Store. Check your connection and try again.",
                kind: .warning
            )
        } else {
            VStack(spacing: DecideSpacing.s) {
                ForEach(subscriptions.products, id: \.id) { product in
                    PlanRow(
                        product: product,
                        isSelected: product.id == selectedProductID,
                        savingPercentage: product.id == SubscriptionService.ProductID.annual
                            ? subscriptions.annualSavingPercentage
                            : nil
                    ) {
                        selectedProductID = product.id
                    }
                }
            }
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: DecideSpacing.xs) {
            Text("Subscriptions renew automatically until cancelled. Cancel any time in your Apple Account settings, at least 24 hours before the period ends.")
                .font(DecideFont.caption)
                .foregroundStyle(DecideColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DecideSpacing.m) {
                if let url = environment.configuration.privacyPolicyURL {
                    Link("Privacy Policy", destination: url).font(DecideFont.caption)
                }
                if let url = environment.configuration.termsURL {
                    Link("Terms of Use", destination: url).font(DecideFont.caption)
                }
            }
            .frame(minHeight: DecideSpacing.minimumTouchTarget * 0.8)
        }
    }

    private func purchase() {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        message = nil
        Task {
            let outcome = await subscriptions.purchase(product)
            isPurchasing = false
            switch outcome {
            case .success:
                environment.analytics.track(.subscriptionStarted)
                dismiss()
            case .pending:
                message = "That purchase needs approval before it can start. I'll unlock Pro as soon as it goes through."
            case .cancelled:
                break
            case .failed(let reason):
                message = reason
            }
        }
    }

    private func restore() {
        isPurchasing = true
        message = nil
        Task {
            let outcome = await subscriptions.restorePurchases()
            isPurchasing = false
            if case .failed(let reason) = outcome { message = reason }
        }
    }
}

private struct PlanRow: View {
    let product: Product
    let isSelected: Bool
    let savingPercentage: Int?
    let action: () -> Void

    private var periodDescription: String {
        guard let subscription = product.subscription else { return "" }
        let unit = subscription.subscriptionPeriod.unit
        let value = subscription.subscriptionPeriod.value
        switch unit {
        case .month: return value == 1 ? "per month" : "every \(value) months"
        case .year: return value == 1 ? "per year" : "every \(value) years"
        case .week: return value == 1 ? "per week" : "every \(value) weeks"
        case .day: return value == 1 ? "per day" : "every \(value) days"
        @unknown default: return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DecideSpacing.m) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? DecideColor.accent : DecideColor.tertiaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(DecideFont.callout.weight(.semibold))
                        .foregroundStyle(DecideColor.primaryText)
                    Text("\(product.displayPrice) \(periodDescription)")
                        .font(DecideFont.footnote)
                        .foregroundStyle(DecideColor.secondaryText)
                }

                Spacer(minLength: DecideSpacing.s)

                if let savingPercentage, savingPercentage > 0 {
                    Text("Save \(savingPercentage)%")
                        .font(DecideFont.caption.weight(.semibold))
                        .foregroundStyle(DecideColor.strong)
                }
            }
            .frame(maxWidth: .infinity, minHeight: DecideSpacing.minimumTouchTarget, alignment: .leading)
            .padding(DecideSpacing.m)
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
}
