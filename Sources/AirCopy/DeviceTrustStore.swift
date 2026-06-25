import Foundation

struct DeviceTrustStore {
    private static let trustedDeviceIDsKey = "trusted-device-ids"
    private static let blockedDeviceIDsKey = "blocked-device-ids"
    private static let autoSyncDisabledDeviceIDsKey = "auto-sync-disabled-device-ids"

    private var trustedDeviceIDs: Set<String>
    private var blockedDeviceIDs: Set<String>
    private var autoSyncDisabledDeviceIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.trustedDeviceIDs = Self.loadStringSet(forKey: Self.trustedDeviceIDsKey, defaults: defaults)
        self.blockedDeviceIDs = Self.loadStringSet(forKey: Self.blockedDeviceIDsKey, defaults: defaults)
        self.autoSyncDisabledDeviceIDs = Self.loadStringSet(forKey: Self.autoSyncDisabledDeviceIDsKey, defaults: defaults)
    }

    func isExplicitlyTrusted(_ deviceID: String) -> Bool {
        trustedDeviceIDs.contains(deviceID)
    }

    func trustState(for deviceID: String, requireDeviceApproval: Bool) -> PeerTrustState {
        if blockedDeviceIDs.contains(deviceID) {
            return .blocked
        }

        if trustedDeviceIDs.contains(deviceID) {
            return .trusted
        }

        return requireDeviceApproval ? .pending : .trusted
    }

    func isAutoSyncEnabled(for deviceID: String, trustState: PeerTrustState) -> Bool {
        guard trustState == .trusted else { return false }
        return !autoSyncDisabledDeviceIDs.contains(deviceID)
    }

    mutating func setAutoSyncEnabled(_ enabled: Bool, for deviceID: String) {
        if enabled {
            autoSyncDisabledDeviceIDs.remove(deviceID)
        } else {
            autoSyncDisabledDeviceIDs.insert(deviceID)
        }

        persistAutoSyncDisabledDeviceIDs()
    }

    mutating func trust(_ deviceID: String) {
        trustedDeviceIDs.insert(deviceID)
        blockedDeviceIDs.remove(deviceID)
        autoSyncDisabledDeviceIDs.remove(deviceID)
        persistTrustSets()
        persistAutoSyncDisabledDeviceIDs()
    }

    mutating func block(_ deviceID: String) {
        blockedDeviceIDs.insert(deviceID)
        trustedDeviceIDs.remove(deviceID)
        autoSyncDisabledDeviceIDs.remove(deviceID)
        persistTrustSets()
        persistAutoSyncDisabledDeviceIDs()
    }

    mutating func enableAutoSyncForAllTrustedDevices(peerIDs: Set<String>, requireDeviceApproval: Bool) -> Set<String> {
        let trustedPeerIDs = peerIDs.filter {
            trustState(for: $0, requireDeviceApproval: requireDeviceApproval) == .trusted
        }
        let autoSyncEligibleDeviceIDs = trustedDeviceIDs.union(trustedPeerIDs)

        autoSyncDisabledDeviceIDs.subtract(autoSyncEligibleDeviceIDs)
        persistAutoSyncDisabledDeviceIDs()
        return autoSyncEligibleDeviceIDs
    }

    private func persistTrustSets() {
        saveStringSet(trustedDeviceIDs, key: Self.trustedDeviceIDsKey)
        saveStringSet(blockedDeviceIDs, key: Self.blockedDeviceIDsKey)
    }

    private func persistAutoSyncDisabledDeviceIDs() {
        saveStringSet(autoSyncDisabledDeviceIDs, key: Self.autoSyncDisabledDeviceIDsKey)
    }

    private func saveStringSet(_ set: Set<String>, key: String) {
        UserDefaults.standard.set(Array(set).sorted(), forKey: key)
    }

    private static func loadStringSet(forKey key: String, defaults: UserDefaults) -> Set<String> {
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values)
    }
}
