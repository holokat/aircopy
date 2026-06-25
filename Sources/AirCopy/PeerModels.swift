import Foundation

enum PeerTrustState: String, Codable, Hashable {
    case pending
    case trusted
    case blocked

    var title: String {
        switch self {
        case .pending:
            return "Approval Needed"
        case .trusted:
            return "Trusted"
        case .blocked:
            return "Blocked"
        }
    }
}

enum DeliveryState: String, Codable, Hashable {
    case pending
    case delivered
    case clipboardUpdated
    case failed
    case skipped

    var title: String {
        switch self {
        case .pending:
            return "Sending"
        case .delivered:
            return "Delivered"
        case .clipboardUpdated:
            return "Ready"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "clock"
        case .delivered:
            return "tray.and.arrow.down"
        case .clipboardUpdated:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "slash.circle"
        }
    }
}

struct DeviceReceipt: Identifiable, Codable, Hashable {
    let id: String
    let deviceID: String
    var deviceName: String
    var state: DeliveryState
    var date: Date

    init(deviceID: String, deviceName: String, state: DeliveryState, date: Date = Date()) {
        self.id = deviceID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.state = state
        self.date = date
    }
}

struct PeerInvitationContext: Codable, Hashable {
    let deviceID: String
    let deviceName: String
}

struct PeerDeviceState: Identifiable, Hashable {
    let id: String
    var displayName: String
    var trustState: PeerTrustState
    var isDiscovered: Bool
    var isConnected: Bool
    var isAutoSyncEnabled: Bool
    var lastSeenAt: Date?
    var lastSyncAt: Date?
    var lastReceiptState: DeliveryState?
    var lastReceiptText: String?
    var lastClipboardSummary: String?
    var encryptedTransport: Bool

    var deviceSymbolName: String {
        let normalizedName = displayName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        if normalizedName.contains("macbook") || normalizedName.contains("laptop") || normalizedName.contains("notebook") {
            return "laptopcomputer"
        }

        return "desktopcomputer"
    }

    var statusSummary: String {
        if isConnected {
            return trustState == .trusted ? "Connected" : trustState.title
        }

        if isDiscovered {
            return trustState.title
        }

        return "Offline"
    }
}

struct AppExclusion: Identifiable, Codable, Hashable {
    let id: String
    let bundleID: String
    var appName: String

    init(bundleID: String, appName: String) {
        self.id = bundleID
        self.bundleID = bundleID
        self.appName = appName
    }
}

struct ProtectedAppRule: Identifiable, Hashable {
    let id: String
    var appName: String
    var matchSummary: String

    init(appName: String, matchSummary: String) {
        self.id = appName.lowercased()
        self.appName = appName
        self.matchSummary = matchSummary
    }
}
