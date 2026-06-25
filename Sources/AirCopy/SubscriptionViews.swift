import SwiftUI

struct SubscriptionGateView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.success(for: colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionManager.paywallTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(subscriptionManager.priceSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }
            }

            Text("Sync clipboard history, text, images, files, and screenshots between your Macs. Cancel anytime in your App Store subscription settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            SubscriptionActionStack(showManageButton: false)
        }
        .padding(18)
        .airCopyPanel(cornerRadius: 18)
    }
}

struct SubscriptionSettingsCard: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(subscriptionManager.hasActiveSubscription ? AirCopyTheme.success(for: colorScheme) : AirCopyTheme.warning(for: colorScheme))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionManager.hasActiveSubscription ? "Subscription active" : "Subscription required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    Text(subscriptionDetailText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }

                Spacer()
            }

            SubscriptionActionStack(showManageButton: true)
        }
        .padding(12)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subscriptionDetailText: String {
        if subscriptionManager.purchaseSkipped {
            return "AirCopy sync is unlocked on this Mac."
        }

        return subscriptionManager.hasActiveSubscription
            ? "AirCopy sync is unlocked on this Apple ID."
            : subscriptionManager.priceSummary
    }
}

struct SubscriptionActionStack: View {
    let showManageButton: Bool

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if subscriptionManager.isCheckingSubscription {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(subscriptionManager.statusMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }
            } else if !subscriptionManager.hasActiveSubscription {
                Button {
                    Task {
                        await subscriptionManager.purchaseMonthlySubscription()
                    }
                } label: {
                    Text(subscriptionManager.purchaseButtonTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AirCopyTheme.buttonTint(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(subscriptionManager.monthlyProduct == nil || subscriptionManager.isPurchasing)

                if subscriptionManager.monthlyProduct == nil {
                    Text("Create the monthly subscription in App Store Connect, then try again.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.warning(for: colorScheme))
                }
            }

            if !subscriptionManager.hasActiveSubscription {
                Button {
                    subscriptionManager.skipPurchase()
                } label: {
                    Text("Skip Purchase")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(colorScheme == .light ? 0.9 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                } label: {
                    Text("Restore Purchases")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(colorScheme == .light ? 0.9 : 0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                if showManageButton {
                    Button {
                        subscriptionManager.openSubscriptionManagement()
                    } label: {
                        Text("Manage")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(colorScheme == .light ? 0.9 : 0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let purchaseErrorMessage = subscriptionManager.purchaseErrorMessage {
                Text(purchaseErrorMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.error(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

#if DEBUG
            Divider()

            Toggle(
                "Development subscription bypass",
                isOn: Binding(
                    get: { subscriptionManager.developmentBypassEnabled },
                    set: { subscriptionManager.setDevelopmentBypassEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .tint(AirCopyTheme.syncTint(for: colorScheme))

            Text("Debug builds only. This control is not compiled into release builds.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
#endif
        }
    }
}
