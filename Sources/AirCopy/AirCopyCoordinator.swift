import AppKit
import Foundation
import MultipeerConnectivity
import SwiftUI

@MainActor
final class AirCopyCoordinator: NSObject, ObservableObject {
    @Published var syncEnabled = true {
        didSet {
            syncEnabled ? startServices() : stopServices()
        }
    }

    @Published var appearancePreference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearancePreferenceKey)
            updateEffectiveColorScheme()
        }
    }

    @Published private(set) var localDeviceName: String
    @Published private(set) var statusText = "Starting..."
    @Published private(set) var discoveredPeerCount = 0
    @Published private(set) var connectedPeerCount = 0
    @Published private(set) var connectedPeerLabels: [String] = []
    @Published private(set) var clipboardHistory: [ClipboardHistoryItem] = []
    @Published private(set) var recentlyCopiedHistoryItemID: UUID?
    @Published private(set) var effectiveColorScheme: ColorScheme
    @Published private(set) var appIconImage: NSImage?

    private let serviceType = "aircopy"
    private let deviceID: String
    private let peerID: MCPeerID

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitedPeerNames = Set<String>()
    private var discoveredPeerNames = Set<String>()
    private var recentMessageIDs: [UUID] = []
    private var recentMessageSet = Set<UUID>()
    private var clipboardTask: Task<Void, Never>?
    private var appearanceTask: Task<Void, Never>?
    private var clearCopiedStateTask: Task<Void, Never>?
    private var lastObservedChangeCount: Int
    private var lastKnownPayload: ClipboardPayload?
    private var pendingRemotePayload: ClipboardPayload?

    private static let appearancePreferenceKey = "appearance-preference"

    override init() {
        let hostName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = hostName?.isEmpty == false ? hostName! : "This Mac"
        let storedAppearance = UserDefaults.standard.string(forKey: Self.appearancePreferenceKey)
        let appearance = AppearancePreference(rawValue: storedAppearance ?? "") ?? .automatic
        self.localDeviceName = resolvedName
        self.appearancePreference = appearance
        self.deviceID = Self.loadOrCreateDeviceID()
        self.peerID = MCPeerID(displayName: Self.sanitizedPeerName(from: resolvedName))
        self.lastObservedChangeCount = NSPasteboard.general.changeCount
        self.lastKnownPayload = Self.readClipboardPayload(from: NSPasteboard.general)
        self.effectiveColorScheme = .light
        self.appIconImage = AppIconProvider.loadAppIcon()
        super.init()

        NSApp.setActivationPolicy(.regular)

        if let appIconImage {
            NSApplication.shared.applicationIconImage = appIconImage
        }

        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.session.delegate = self
        updateEffectiveColorScheme()

        if let payload = lastKnownPayload {
            recordHistory(payload: payload, source: "Current clipboard on this Mac", senderName: resolvedName, date: Date())
        }

        startServices()
        startClipboardMonitor()
        startAppearanceMonitor()
    }

    deinit {
        clipboardTask?.cancel()
        appearanceTask?.cancel()
        clearCopiedStateTask?.cancel()
    }

    var latestClipboardItem: ClipboardHistoryItem? {
        clipboardHistory.first
    }

    var menuBarSymbolName: String {
        if latestClipboardItem?.kind == .image {
            return connectedPeerCount > 0 ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled"
        }
        return connectedPeerCount > 0 ? "doc.on.clipboard.fill" : "doc.on.clipboard"
    }

    func restoreHistoryItem(_ item: ClipboardHistoryItem) {
        pendingRemotePayload = nil
        lastKnownPayload = item.payload
        writePayloadToPasteboard(item.payload)
        updateHistoryItem(id: item.id, source: "Restored from history", senderName: localDeviceName, date: Date())
        markHistoryItemCopied(item.id)
        playSelectionSound()
        broadcastLocalPayload(item.payload)
    }

    func clearClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        lastObservedChangeCount = pasteboard.changeCount
        lastKnownPayload = nil
        pendingRemotePayload = nil
        statusText = connectedPeerCount == 0
            ? "Clipboard cleared. Waiting for peers."
            : "Clipboard cleared locally."
    }

    func clearHistory() {
        clipboardHistory.removeAll()
        statusText = "Recent clips cleared."
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func startServices() {
        guard advertiser == nil, browser == nil else { return }

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["deviceID": deviceID],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        statusText = "Advertising and searching for nearby Macs..."
    }

    private func stopServices() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        invitedPeerNames.removeAll()
        discoveredPeerNames.removeAll()
        discoveredPeerCount = 0
        session.disconnect()
        connectedPeerLabels = []
        connectedPeerCount = 0
        statusText = "Clipboard sync disabled"
    }

    private func startClipboardMonitor() {
        clipboardTask?.cancel()
        clipboardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    self?.pollClipboard()
                }
            }
        }
    }

    private func startAppearanceMonitor() {
        appearanceTask?.cancel()
        appearanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await MainActor.run {
                    self?.updateEffectiveColorScheme()
                }
            }
        }
    }

    private func pollClipboard() {
        guard syncEnabled else { return }

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = changeCount

        guard let payload = Self.readClipboardPayload(from: pasteboard) else {
            lastKnownPayload = nil
            return
        }

        if pendingRemotePayload == payload {
            pendingRemotePayload = nil
            lastKnownPayload = payload
            recordHistory(payload: payload, source: "Received from a peer", senderName: "Peer", date: Date())
            return
        }

        guard payload != lastKnownPayload else { return }

        lastKnownPayload = payload
        recordHistory(payload: payload, source: "Copied on this Mac", senderName: localDeviceName, date: Date())
        broadcastLocalPayload(payload)
    }

    private func broadcastLocalPayload(_ payload: ClipboardPayload) {
        let message = ClipboardMessage(
            id: UUID(),
            senderID: deviceID,
            senderName: localDeviceName,
            payload: payload,
            sentAt: Date()
        )

        rememberMessageID(message.id)

        guard !session.connectedPeers.isEmpty else {
            statusText = "Saved locally. Waiting for a peer to connect."
            return
        }

        do {
            let payloadData = try JSONEncoder().encode(message)
            try session.send(payloadData, toPeers: session.connectedPeers, with: .reliable)
            let noun = payload.kind == .image ? "image" : "text"
            statusText = "Synced \(noun) clip to \(connectedPeerCount) peer(s)."
        } catch {
            statusText = "Failed to send clipboard item: \(error.localizedDescription)"
        }
    }

    private func applyRemoteClipboard(_ message: ClipboardMessage) {
        guard message.senderID != deviceID else { return }
        guard !recentMessageSet.contains(message.id) else { return }

        rememberMessageID(message.id)

        if lastKnownPayload == message.payload {
            statusText = "Peer \(message.senderName) sent the same clip again."
            return
        }

        pendingRemotePayload = message.payload
        lastKnownPayload = message.payload
        writePayloadToPasteboard(message.payload)
        recordHistory(
            payload: message.payload,
            source: "Received from \(message.senderName)",
            senderName: message.senderName,
            date: message.sentAt
        )

        let noun = message.payload.kind == .image ? "image" : "text"
        statusText = "Received \(noun) clip from \(message.senderName)."
    }

    private func writePayloadToPasteboard(_ payload: ClipboardPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch payload.kind {
        case .text:
            if let text = payload.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = payload.imageData, let image = NSImage(data: data) {
                if !pasteboard.writeObjects([image]) {
                    pasteboard.setData(data, forType: .png)
                }
            }
        }

        lastObservedChangeCount = pasteboard.changeCount
    }

    private func recordHistory(payload: ClipboardPayload, source: String, senderName: String, date: Date) {
        let item = ClipboardHistoryItem(
            id: UUID(),
            payload: payload,
            source: source,
            senderName: senderName,
            date: date
        )

        clipboardHistory.removeAll { $0.payload == payload }
        clipboardHistory.insert(item, at: 0)

        if clipboardHistory.count > 3 {
            clipboardHistory = Array(clipboardHistory.prefix(3))
        }
    }

    private func updateHistoryItem(id: UUID, source: String, senderName: String, date: Date) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == id }) else { return }

        let existing = clipboardHistory[index]
        clipboardHistory[index] = ClipboardHistoryItem(
            id: existing.id,
            payload: existing.payload,
            source: source,
            senderName: senderName,
            date: date
        )
    }

    private func updateEffectiveColorScheme(for date: Date = Date()) {
        switch appearancePreference {
        case .automatic:
            let hour = Calendar.current.component(.hour, from: date)
            effectiveColorScheme = (7..<18).contains(hour) ? .light : .dark
        case .light:
            effectiveColorScheme = .light
        case .dark:
            effectiveColorScheme = .dark
        }
    }

    private func playSelectionSound() {
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func markHistoryItemCopied(_ id: UUID) {
        guard let item = clipboardHistory.first(where: { $0.id == id }) else { return }

        recentlyCopiedHistoryItemID = item.id
        clearCopiedStateTask?.cancel()
        clearCopiedStateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                guard self?.recentlyCopiedHistoryItemID == item.id else { return }
                self?.recentlyCopiedHistoryItemID = nil
            }
        }
    }

    private func rememberMessageID(_ id: UUID) {
        recentMessageIDs.append(id)
        recentMessageSet.insert(id)

        if recentMessageIDs.count > 256 {
            let removed = recentMessageIDs.removeFirst()
            recentMessageSet.remove(removed)
        }
    }

    private func refreshConnections() {
        connectedPeerLabels = session.connectedPeers
            .map(\.displayName)
            .sorted()
        connectedPeerCount = connectedPeerLabels.count
        discoveredPeerCount = discoveredPeerNames.count
    }

    private static func loadOrCreateDeviceID() -> String {
        let defaults = UserDefaults.standard
        let key = "device-id"

        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString.lowercased()
        defaults.set(newID, forKey: key)
        return newID
    }

    private static func readClipboardPayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        if let imageData = pngData(from: pasteboard), !imageData.isEmpty {
            return ClipboardPayload(imageData: imageData)
        }

        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ClipboardPayload(text: text)
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return pngData(from: image)
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            return pngData(from: image)
        }

        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func sanitizedPeerName(from rawName: String) -> String {
        let invalidCharacterSet = CharacterSet(charactersIn: ":")
        let cleaned = rawName
            .components(separatedBy: invalidCharacterSet)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "AirCopy Mac"
        }

        return String(cleaned.prefix(63))
    }
}

private final class InvitationHandlerBox: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void

    init(_ handler: @escaping (Bool, MCSession?) -> Void) {
        self.handler = handler
    }
}

private final class PeerIDBox: @unchecked Sendable {
    let peerID: MCPeerID

    init(_ peerID: MCPeerID) {
        self.peerID = peerID
    }
}

extension AirCopyCoordinator: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let peerName = peerID.displayName
        let handlerBox = InvitationHandlerBox(invitationHandler)

        Task { @MainActor [weak self] in
            guard let self else {
                handlerBox.handler(false, nil)
                return
            }

            discoveredPeerNames.insert(peerName)
            refreshConnections()
            statusText = "Invitation from \(peerName). Connecting..."
            handlerBox.handler(syncEnabled, syncEnabled ? session : nil)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.statusText = "Advertising failed: \(error.localizedDescription)"
        }
    }
}

extension AirCopyCoordinator: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let peerName = peerID.displayName
        let peerBox = PeerIDBox(peerID)

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard peerName != self.peerID.displayName else { return }

            discoveredPeerNames.insert(peerName)
            refreshConnections()

            guard !session.connectedPeers.contains(where: { $0.displayName == peerName }) else {
                statusText = "Connected to \(connectedPeerCount) peer(s)."
                return
            }

            guard !invitedPeerNames.contains(peerName) else { return }

            invitedPeerNames.insert(peerName)
            statusText = "Found \(peerName). Connecting..."
            self.browser?.invitePeer(peerBox.peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerName = peerID.displayName

        Task { @MainActor [weak self] in
            guard let self else { return }
            discoveredPeerNames.remove(peerName)
            invitedPeerNames.remove(peerName)
            refreshConnections()

            if connectedPeerCount == 0 {
                statusText = "Searching for AirCopy peers..."
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.statusText = "Browsing failed: \(error.localizedDescription)"
        }
    }
}

extension AirCopyCoordinator: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peerName = peerID.displayName

        Task { @MainActor [weak self] in
            guard let self else { return }

            switch state {
            case .connected:
                discoveredPeerNames.insert(peerName)
                invitedPeerNames.remove(peerName)
                refreshConnections()
                statusText = "Connected to \(connectedPeerCount) peer(s)."

                if let payload = lastKnownPayload {
                    broadcastLocalPayload(payload)
                }
            case .connecting:
                discoveredPeerNames.insert(peerName)
                refreshConnections()
                statusText = "Connecting to \(peerName)..."
            case .notConnected:
                invitedPeerNames.remove(peerName)
                refreshConnections()
                statusText = connectedPeerCount == 0
                    ? "Searching for AirCopy peers..."
                    : "Connected to \(connectedPeerCount) peer(s)."
            @unknown default:
                statusText = "Peer state changed."
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peerName = peerID.displayName

        do {
            let message = try JSONDecoder().decode(ClipboardMessage.self, from: data)
            Task { @MainActor [weak self] in
                self?.applyRemoteClipboard(message)
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.statusText = "Received invalid clip data from \(peerName)."
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
