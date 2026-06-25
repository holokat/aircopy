import AppKit
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    static let monthlyProductID = "dev.aircopy.app.pro.monthly"

    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRefreshingEntitlements = true
    @Published private(set) var isPurchasing = false
    @Published private(set) var statusMessage = "Checking your App Store subscription..."
    @Published private(set) var purchaseErrorMessage: String?
    @Published private(set) var isEligibleForIntroOffer: Bool?
    @Published private(set) var purchaseSkipped = false
#if DEBUG
    @Published private(set) var developmentBypassEnabled = false
#endif

    private static let productIDs: Set<String> = [monthlyProductID]
    private static let purchaseSkippedKey = "subscription-purchase-skipped"
#if DEBUG
    private static let developmentBypassKey = "development-subscription-bypass-enabled"
#endif
    private let defaults: UserDefaults
    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStarted = false

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var hasActiveSubscription: Bool {
        if purchaseSkipped { return true }
#if DEBUG
        if developmentBypassEnabled { return true }
#endif
        return !activeProductIDs.isDisjoint(with: Self.productIDs)
    }

    var isCheckingSubscription: Bool {
        isLoadingProducts || isRefreshingEntitlements
    }

    var priceSummary: String {
        guard let monthlyProduct else {
            return "$9.99 per month after the free trial"
        }

        guard shouldShowIntroOffer else {
            return "\(monthlyProduct.displayPrice) per month"
        }

        return "\(monthlyProduct.displayPrice) per month after the \(introOfferLabel)"
    }

    var purchaseButtonTitle: String {
        if isPurchasing { return "Starting..." }
        return shouldShowIntroOffer ? "Start \(introOfferLabel.capitalized)" : "Subscribe"
    }

    var paywallTitle: String {
        shouldShowIntroOffer ? "Start your \(introOfferLabel)" : "Subscribe to AirCopy"
    }

    private var shouldShowIntroOffer: Bool {
        guard let monthlyProduct else { return true }
        guard let introductoryOffer = monthlyProduct.subscription?.introductoryOffer,
              introductoryOffer.paymentMode == .freeTrial else {
            return false
        }

        return isEligibleForIntroOffer != false
    }

    private var introOfferLabel: String {
        guard let offer = monthlyProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return "free trial"
        }

        return "\(Self.label(for: offer.period)) free trial"
    }

    private var unsubscribedStatusMessage: String {
        shouldShowIntroOffer
            ? "Start your \(introOfferLabel) to sync between Macs."
            : "Subscribe to AirCopy to sync between Macs."
    }

    private var skippedStatusMessage: String {
        "Purchase skipped. AirCopy is unlocked on this Mac."
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        purchaseSkipped = defaults.bool(forKey: Self.purchaseSkippedKey)
#if DEBUG
        developmentBypassEnabled = Self.loadDevelopmentBypassEnabled()
#endif
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func prepareForTermination() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

#if DEBUG
        if developmentBypassEnabled {
            statusMessage = "Development subscription bypass is enabled."
        }
#endif
        if purchaseSkipped {
            statusMessage = skippedStatusMessage
        }

        transactionUpdatesTask = observeTransactionUpdates()
        await refreshEntitlements()
        await loadProducts()
    }

#if DEBUG
    func setDevelopmentBypassEnabled(_ enabled: Bool) {
        developmentBypassEnabled = enabled
        defaults.set(enabled, forKey: Self.developmentBypassKey)
        statusMessage = enabled
            ? "Development subscription bypass is enabled."
            : unsubscribedStatusMessage
    }
#endif

    func skipPurchase() {
        purchaseSkipped = true
        defaults.set(true, forKey: Self.purchaseSkippedKey)
        purchaseErrorMessage = nil
        statusMessage = skippedStatusMessage
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetchedProducts = try await Product.products(for: Self.productIDs)
            products = fetchedProducts.sorted { $0.displayName < $1.displayName }
            await refreshIntroOfferEligibility()

            if purchaseSkipped {
                statusMessage = skippedStatusMessage
            } else if fetchedProducts.isEmpty {
                statusMessage = "The AirCopy subscription is not available from the App Store yet."
            } else if hasActiveSubscription {
                statusMessage = "Your AirCopy subscription is active."
            } else {
                statusMessage = unsubscribedStatusMessage
            }
        } catch {
            products = []
            isEligibleForIntroOffer = nil
            if purchaseSkipped {
                purchaseErrorMessage = nil
                statusMessage = skippedStatusMessage
            } else {
                purchaseErrorMessage = "Unable to load the AirCopy subscription from the App Store."
                statusMessage = "The App Store subscription could not be loaded."
            }
        }
    }

    func refreshEntitlements() async {
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        var currentProductIDs = Set<String>()

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else {
                continue
            }

            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }

            currentProductIDs.insert(transaction.productID)
        }

        activeProductIDs = currentProductIDs
#if DEBUG
        if developmentBypassEnabled {
            statusMessage = "Development subscription bypass is enabled."
            return
        }
#endif
        if purchaseSkipped {
            statusMessage = skippedStatusMessage
            return
        }
        statusMessage = hasActiveSubscription
            ? "Your AirCopy subscription is active."
            : unsubscribedStatusMessage
    }

    func purchaseMonthlySubscription() async {
        guard let product = monthlyProduct else {
            purchaseErrorMessage = "The AirCopy subscription is not available from the App Store yet."
            await loadProducts()
            return
        }

        isPurchasing = true
        purchaseErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseErrorMessage = "The App Store could not verify this purchase."
                    return
                }

                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                statusMessage = "The purchase is pending approval."
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            @unknown default:
                statusMessage = "The App Store did not complete the purchase."
            }
        } catch {
            purchaseErrorMessage = "The App Store could not complete the purchase."
        }
    }

    func restorePurchases() async {
        purchaseErrorMessage = nil
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = "The App Store could not restore purchases right now."
        }
    }

    func openSubscriptionManagement() {
        guard let url = URL(string: "macappstore://apps.apple.com/account/subscriptions") else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await verification in Transaction.updates {
                await self?.handleTransactionUpdate(verification)
            }
        }
    }

    private func refreshIntroOfferEligibility() async {
        guard let subscription = monthlyProduct?.subscription else {
            isEligibleForIntroOffer = nil
            return
        }

        isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
    }

    private func handleTransactionUpdate(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else {
            purchaseErrorMessage = "The App Store could not verify an updated purchase."
            return
        }

        await transaction.finish()
        await refreshEntitlements()
    }

#if DEBUG
    private static func loadDevelopmentBypassEnabled() -> Bool {
        ProcessInfo.processInfo.environment["AIRCOPY_SUBSCRIPTION_BYPASS"] == "1"
            || UserDefaults.standard.bool(forKey: developmentBypassKey)
    }
#endif

    private static func label(for period: Product.SubscriptionPeriod) -> String {
        let unit: String

        switch period.unit {
        case .day:
            unit = "day"
        case .week:
            unit = "week"
        case .month:
            unit = "month"
        case .year:
            unit = "year"
        @unknown default:
            unit = "period"
        }

        return "\(period.value)-\(unit)"
    }
}
