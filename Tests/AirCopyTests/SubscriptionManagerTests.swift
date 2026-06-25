import Foundation
import Testing
@testable import AirCopy

@MainActor
struct SubscriptionManagerTests {
    @Test
    func skipPurchaseUnlocksSubscriptionAccess() {
        let defaults = UserDefaults(suiteName: "SubscriptionManagerTests.skipPurchaseUnlocksSubscriptionAccess")!
        defaults.removePersistentDomain(forName: "SubscriptionManagerTests.skipPurchaseUnlocksSubscriptionAccess")
        let manager = SubscriptionManager(defaults: defaults)

        #expect(!manager.hasActiveSubscription)

        manager.skipPurchase()

        #expect(manager.hasActiveSubscription)
        #expect(manager.purchaseSkipped)
    }

    @Test
    func skipPurchasePersistsAcrossManagerInstances() {
        let defaults = UserDefaults(suiteName: "SubscriptionManagerTests.skipPurchasePersistsAcrossManagerInstances")!
        defaults.removePersistentDomain(forName: "SubscriptionManagerTests.skipPurchasePersistsAcrossManagerInstances")

        SubscriptionManager(defaults: defaults).skipPurchase()
        let reloadedManager = SubscriptionManager(defaults: defaults)

        #expect(reloadedManager.hasActiveSubscription)
        #expect(reloadedManager.purchaseSkipped)
    }
}
