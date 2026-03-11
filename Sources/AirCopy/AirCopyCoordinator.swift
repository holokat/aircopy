import AppKit
import Foundation
import MultipeerConnectivity
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AirCopyCoordinator: NSObject, ObservableObject {
    private enum SaveReceivedPayloadResult {
        case skipped
        case saved(String)
        case failed(String)
    }

    @Published var syncEnabled = true {
        didSet {
            guard syncEnabled != oldValue else { return }

            if syncEnabled {
                startServices()
                statusText = "Sync to All is on."
            } else {
                temporarySyncUntil = nil
                statusText = "Sync to All is off. Trusted Macs stay available for manual sends."
            }
        }
    }

    @Published var imageSyncEnabled = true {
        didSet {
            UserDefaults.standard.set(imageSyncEnabled, forKey: Self.imageSyncEnabledKey)
            statusText = imageSyncEnabled ? "Image sync enabled." : "Image sync paused."
        }
    }

    @Published var importSystemScreenshotsEnabled = true {
        didSet {
            UserDefaults.standard.set(importSystemScreenshotsEnabled, forKey: Self.importSystemScreenshotsEnabledKey)
            restartScreenshotImportMonitorIfNeeded()
            statusText = importSystemScreenshotsEnabled
                ? "Importing standard macOS screenshots."
                : "Standard macOS screenshot import is off."
        }
    }

    @Published var saveReceivedItemsToDiskEnabled = false {
        didSet {
            UserDefaults.standard.set(saveReceivedItemsToDiskEnabled, forKey: Self.saveReceivedItemsToDiskEnabledKey)
        }
    }

    @Published var saveReceivedImagesToDisk = true {
        didSet {
            UserDefaults.standard.set(saveReceivedImagesToDisk, forKey: Self.saveReceivedImagesToDiskKey)
        }
    }

    @Published var saveReceivedTextToDisk = true {
        didSet {
            UserDefaults.standard.set(saveReceivedTextToDisk, forKey: Self.saveReceivedTextToDiskKey)
        }
    }

    @Published var saveReceivedFilesToDisk = true {
        didSet {
            UserDefaults.standard.set(saveReceivedFilesToDisk, forKey: Self.saveReceivedFilesToDiskKey)
        }
    }

    @Published var requireDeviceApproval = true {
        didSet {
            UserDefaults.standard.set(requireDeviceApproval, forKey: Self.requireDeviceApprovalKey)
        }
    }

    @Published var settingsPresented = false

    @Published var appearancePreference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearancePreferenceKey)
            updateEffectiveColorScheme()
        }
    }

    @Published private(set) var localDeviceName: String
    @Published private(set) var statusText = "Starting..."
    @Published private(set) var peerDevices: [PeerDeviceState] = []
    @Published private(set) var clipboardHistory: [ClipboardHistoryItem] = []
    @Published private(set) var recentlyCopiedHistoryItemID: UUID?
    @Published private(set) var effectiveColorScheme: ColorScheme
    @Published private(set) var appIconImage: NSImage?
    @Published private(set) var savedItemsBaseDirectoryPath: String
    @Published private(set) var temporarySyncUntil: Date? {
        didSet {
            if let temporarySyncUntil {
                UserDefaults.standard.set(temporarySyncUntil, forKey: Self.temporarySyncUntilKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.temporarySyncUntilKey)
            }

            scheduleSyncExpirationTask()
        }
    }
    @Published private(set) var frontmostApplicationName: String
    @Published private(set) var excludedApplications: [AppExclusion] = []

    private let serviceType = "aircopy"
    private let deviceID: String
    private let peerID: MCPeerID
    private let maxHistoryItems = 64
    private let maxInlineAttachmentBytes: Int64 = 8 * 1024 * 1024
    private let inviteRetryInterval: TimeInterval = 3
    private let protectedPasswordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.roboform.RoboForm",
        "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc"
    ]
    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
        "tif", "tiff", "bmp", "avif", "jxl", "icns"
    ]

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerIDByDeviceID: [String: MCPeerID] = [:]
    private var peerDisplayNameToDeviceID: [String: String] = [:]
    private var peerStateByID: [String: PeerDeviceState] = [:]
    private var lastInviteAttemptByDeviceID: [String: Date] = [:]
    private var trustedDeviceIDs: Set<String>
    private var blockedDeviceIDs: Set<String>
    private var autoSyncDisabledDeviceIDs: Set<String>
    private var pinnedFingerprints: Set<String>
    private var favoriteFingerprints: Set<String>
    private var excludedAppMap: [String: String]
    private var recentMessageIDs: [UUID] = []
    private var recentMessageSet = Set<UUID>()
    private var outboundMessageHistoryMap: [UUID: UUID] = [:]
    private var clipboardTask: Task<Void, Never>?
    private var appearanceTask: Task<Void, Never>?
    private var syncExpirationTask: Task<Void, Never>?
    private var screenshotImportTask: Task<Void, Never>?
    private var clearCopiedStateTask: Task<Void, Never>?
    private var lastObservedChangeCount: Int
    private var lastKnownPayload: ClipboardPayload?
    private var pendingRemotePayload: ClipboardPayload?
    private var knownScreenshotFileSignatures = Set<String>()
    private var screenshotMonitorFolderPath: String?

    private static let appearancePreferenceKey = "appearance-preference"
    private static let imageSyncEnabledKey = "image-sync-enabled"
    private static let importSystemScreenshotsEnabledKey = "import-system-screenshots-enabled"
    private static let saveReceivedItemsToDiskEnabledKey = "save-received-items-to-disk-enabled"
    private static let saveReceivedImagesToDiskKey = "save-received-images-to-disk"
    private static let saveReceivedTextToDiskKey = "save-received-text-to-disk"
    private static let saveReceivedFilesToDiskKey = "save-received-files-to-disk"
    private static let savedItemsBaseDirectoryPathKey = "saved-items-base-directory-path"
    private static let temporarySyncUntilKey = "temporary-sync-until"
    private static let trustedDeviceIDsKey = "trusted-device-ids"
    private static let blockedDeviceIDsKey = "blocked-device-ids"
    private static let autoSyncDisabledDeviceIDsKey = "auto-sync-disabled-device-ids"
    private static let pinnedFingerprintsKey = "pinned-fingerprints"
    private static let favoriteFingerprintsKey = "favorite-fingerprints"
    private static let excludedAppsKey = "excluded-app-map"
    private static let requireDeviceApprovalKey = "require-device-approval"

    override init() {
        let hostName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = hostName?.isEmpty == false ? hostName! : "This Mac"
        let defaults = UserDefaults.standard
        let storedAppearance = defaults.string(forKey: Self.appearancePreferenceKey)
        let appearance = AppearancePreference(rawValue: storedAppearance ?? "") ?? .automatic
        let frontmost = Self.frontmostApplicationInfo()

        self.localDeviceName = resolvedName
        self.appearancePreference = appearance
        self.deviceID = Self.loadOrCreateDeviceID()
        self.peerID = MCPeerID(displayName: Self.sanitizedPeerName(from: resolvedName))
        self.imageSyncEnabled = defaults.object(forKey: Self.imageSyncEnabledKey) as? Bool ?? true
        self.importSystemScreenshotsEnabled = defaults.object(forKey: Self.importSystemScreenshotsEnabledKey) as? Bool ?? true
        self.saveReceivedItemsToDiskEnabled = defaults.object(forKey: Self.saveReceivedItemsToDiskEnabledKey) as? Bool ?? false
        self.saveReceivedImagesToDisk = defaults.object(forKey: Self.saveReceivedImagesToDiskKey) as? Bool ?? true
        self.saveReceivedTextToDisk = defaults.object(forKey: Self.saveReceivedTextToDiskKey) as? Bool ?? true
        self.saveReceivedFilesToDisk = defaults.object(forKey: Self.saveReceivedFilesToDiskKey) as? Bool ?? true
        self.savedItemsBaseDirectoryPath = defaults.string(forKey: Self.savedItemsBaseDirectoryPathKey)
            ?? Self.defaultSavedItemsBaseDirectory.path
        self.requireDeviceApproval = defaults.object(forKey: Self.requireDeviceApprovalKey) as? Bool ?? true
        self.temporarySyncUntil = defaults.object(forKey: Self.temporarySyncUntilKey) as? Date
        self.trustedDeviceIDs = Self.loadStringSet(forKey: Self.trustedDeviceIDsKey)
        self.blockedDeviceIDs = Self.loadStringSet(forKey: Self.blockedDeviceIDsKey)
        self.autoSyncDisabledDeviceIDs = Self.loadStringSet(forKey: Self.autoSyncDisabledDeviceIDsKey)
        self.pinnedFingerprints = Self.loadStringSet(forKey: Self.pinnedFingerprintsKey)
        self.favoriteFingerprints = Self.loadStringSet(forKey: Self.favoriteFingerprintsKey)
        self.excludedAppMap = Self.loadStringDictionary(forKey: Self.excludedAppsKey)
        self.frontmostApplicationName = frontmost.name ?? "Unknown App"
        self.effectiveColorScheme = .light
        self.appIconImage = AppIconProvider.loadAppIcon()
        self.lastObservedChangeCount = NSPasteboard.general.changeCount
        self.lastKnownPayload = Self.readClipboardPayload(
            from: NSPasteboard.general,
            maxInlineAttachmentBytes: 8 * 1024 * 1024,
            sourceAppBundleID: frontmost.bundleID,
            sourceAppName: frontmost.name
        )
        super.init()

        self.excludedApplications = excludedAppMap
            .map { AppExclusion(bundleID: $0.key, appName: $0.value) }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }

        NSApp.setActivationPolicy(.regular)

        if let appIconImage {
            NSApplication.shared.applicationIconImage = appIconImage
        }

        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.session.delegate = self
        updateEffectiveColorScheme()

        if let temporarySyncUntil, temporarySyncUntil <= Date() {
            self.temporarySyncUntil = nil
            self.syncEnabled = false
        }

        if let payload = lastKnownPayload, !shouldSuppressSync(for: payload) {
            _ = recordHistory(
                payload: payload,
                source: "Current clipboard on this Mac",
                senderName: resolvedName,
                date: Date()
            )
        }

        startServices()
        startClipboardMonitor()
        startAppearanceMonitor()
        scheduleSyncExpirationTask()
        restartScreenshotImportMonitorIfNeeded()
        statusText = connectedPeerCount == 0 ? "Approve a nearby Mac or keep syncing locally." : "Ready."
    }

    deinit {
        clipboardTask?.cancel()
        appearanceTask?.cancel()
        syncExpirationTask?.cancel()
        screenshotImportTask?.cancel()
        clearCopiedStateTask?.cancel()
    }

    var discoveredPeerCount: Int {
        peerDevices.filter(\.isDiscovered).count
    }

    var connectedPeerCount: Int {
        connectedDeviceIDs.count
    }

    var connectedPeerLabels: [String] {
        peerDevices
            .filter { connectedDeviceIDs.contains($0.id) }
            .map(\.displayName)
            .sorted()
    }

    var latestClipboardItem: ClipboardHistoryItem? {
        clipboardHistory.sorted(by: historySort).first
    }

    var latestImageItem: ClipboardHistoryItem? {
        clipboardHistory.first(where: { $0.kind == .image })
    }

    var hasClearableHistory: Bool {
        clipboardHistory.contains(where: { !$0.isPinned && !$0.isFavorite })
    }

    var trustedConnectedPeers: [PeerDeviceState] {
        peerDevices.filter { connectedDeviceIDs.contains($0.id) && $0.trustState == .trusted }
    }

    var autoSyncPeers: [PeerDeviceState] {
        trustedConnectedPeers.filter(\.isAutoSyncEnabled)
    }

    var menuBarSymbolName: String {
        guard let latestClipboardItem else {
            return connectedPeerCount > 0 ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        }

        if latestClipboardItem.kind == .image {
            return connectedPeerCount > 0 ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled"
        }

        return connectedPeerCount > 0 ? "doc.on.clipboard.fill" : "doc.on.clipboard"
    }

    var syncModeSummary: String {
        guard syncEnabled else { return "Manual" }

        if let temporarySyncUntil {
            let minutes = max(1, Int(temporarySyncUntil.timeIntervalSinceNow / 60))
            return "On for \(minutes)m"
        }

        let trustedCount = peerDevices.filter { $0.trustState == .trusted }.count
        let enabledCount = peerDevices.filter { $0.trustState == .trusted && $0.isAutoSyncEnabled }.count

        if trustedCount > 0, enabledCount < trustedCount {
            return "\(enabledCount) of \(trustedCount) Macs"
        }

        return "All trusted Macs"
    }

    var customExclusionCount: Int {
        excludedApplications.count
    }

    var screenshotImportFolderDisplayPath: String {
        (systemScreenshotFolderURL.path as NSString).abbreviatingWithTildeInPath
    }

    var savedItemsDirectoryDisplayPath: String {
        (savedItemsBaseDirectoryPath as NSString).abbreviatingWithTildeInPath
    }

    func filteredHistory(searchText: String, filter: HistoryFilter) -> [ClipboardHistoryItem] {
        clipboardHistory
            .filter { item in
                guard filter.matches(item.kind) else { return false }
                guard !searchText.isEmpty else { return true }
                return item.payload.searchableText.contains(searchText.lowercased())
            }
            .sorted(by: historySort)
    }

    func restoreHistoryItem(_ item: ClipboardHistoryItem) {
        restoreHistoryItem(id: item.id)
    }

    func restoreHistoryItem(id: UUID) {
        guard let item = clipboardHistory.first(where: { $0.id == id }) else {
            statusText = "That history item is no longer available."
            return
        }

        pendingRemotePayload = nil
        lastKnownPayload = item.payload
        writePayloadToPasteboard(item.payload)
        updateHistoryItem(
            id: item.id,
            source: "Restored from history",
            senderName: localDeviceName,
            date: Date()
        )
        markHistoryItemCopied(item.id)
        playSelectionSound()

        if syncEnabled {
            sendPayload(item.payload, toDeviceIDs: autoSyncPeers.map(\.id), historyItemID: item.id)
        }
    }

    func sendHistoryItem(_ item: ClipboardHistoryItem, to deviceID: String) {
        sendPayload(item.payload, toDeviceIDs: [deviceID], historyItemID: item.id, sendOnly: true)
    }

    func sendCurrentClipboard(to deviceID: String) {
        let frontmost = Self.frontmostApplicationInfo()
        frontmostApplicationName = frontmost.name ?? frontmostApplicationName

        guard let payload = Self.readClipboardPayload(
            from: NSPasteboard.general,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: frontmost.bundleID,
            sourceAppName: frontmost.name
        ) else {
            statusText = "Nothing sendable is in the clipboard."
            return
        }

        guard !shouldSuppressSync(for: payload) else { return }

        let item = recordHistory(
            payload: payload,
            source: "Sent without replacing local clipboard",
            senderName: localDeviceName,
            date: Date()
        )
        sendPayload(payload, toDeviceIDs: [deviceID], historyItemID: item.id, sendOnly: true)
    }

    func startTemporarySync(minutes: Int = 10) {
        syncEnabled = true
        temporarySyncUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        statusText = "Sync enabled for \(minutes) minutes."
    }

    func setSyncToAllEnabled(_ enabled: Bool) {
        if enabled {
            temporarySyncUntil = nil
            enableAutoSyncForAllTrustedDevices()
            syncEnabled = true
        } else {
            syncEnabled = false
        }
    }

    func cancelTemporarySync() {
        temporarySyncUntil = nil
        statusText = syncEnabled ? "Temporary sync cleared. Sync stays on." : "Temporary sync cleared."
    }

    func clearClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        lastObservedChangeCount = pasteboard.changeCount
        lastKnownPayload = nil
        pendingRemotePayload = nil
        statusText = "Cleared this Mac only."
    }

    func clearHistory() {
        clipboardHistory.removeAll()
        statusText = "Local history cleared."
    }

    func clearNonRetainedHistory() {
        let removedCount = clipboardHistory.reduce(into: 0) { count, item in
            if !item.isPinned && !item.isFavorite {
                count += 1
            }
        }

        guard removedCount > 0 else {
            statusText = "Only pinned and favorited clips remain."
            return
        }

        clipboardHistory.removeAll { !$0.isPinned && !$0.isFavorite }
        statusText = "Cleared \(removedCount) history item\(removedCount == 1 ? "" : "s")."
    }

    func togglePin(for item: ClipboardHistoryItem) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardHistory[index].isPinned.toggle()

        if clipboardHistory[index].isPinned {
            pinnedFingerprints.insert(clipboardHistory[index].fingerprint)
        } else {
            pinnedFingerprints.remove(clipboardHistory[index].fingerprint)
        }

        saveStringSet(pinnedFingerprints, key: Self.pinnedFingerprintsKey)
        sortAndTrimHistory()
    }

    func toggleFavorite(for item: ClipboardHistoryItem) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardHistory[index].isFavorite.toggle()

        if clipboardHistory[index].isFavorite {
            favoriteFingerprints.insert(clipboardHistory[index].fingerprint)
        } else {
            favoriteFingerprints.remove(clipboardHistory[index].fingerprint)
        }

        saveStringSet(favoriteFingerprints, key: Self.favoriteFingerprintsKey)
        sortAndTrimHistory()
    }

    func setAutoSyncEnabled(_ enabled: Bool, for deviceID: String) {
        guard trustedDeviceIDs.contains(deviceID) else { return }

        if enabled {
            autoSyncDisabledDeviceIDs.remove(deviceID)
        } else {
            autoSyncDisabledDeviceIDs.insert(deviceID)
        }

        saveStringSet(autoSyncDisabledDeviceIDs, key: Self.autoSyncDisabledDeviceIDsKey)
        updatePeer(deviceID: deviceID) { peer in
            peer.isAutoSyncEnabled = enabled
        }
        refreshPeerDevices()

        let deviceName = peerStateByID[deviceID]?.displayName ?? "device"
        statusText = enabled
            ? "Auto-sync enabled for \(deviceName)."
            : "Auto-sync paused for \(deviceName). Manual send stays available."
    }

    func isAutoSyncEnabled(for deviceID: String) -> Bool {
        autoSyncEnabledState(for: deviceID)
    }

    func chooseSavedItemsDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose AirCopy Save Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = savedItemsBaseDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        savedItemsBaseDirectoryPath = url.path
        UserDefaults.standard.set(savedItemsBaseDirectoryPath, forKey: Self.savedItemsBaseDirectoryPathKey)
        statusText = "Received items will save to \(savedItemsDirectoryDisplayPath)."
    }

    func openSavedItemsDirectory() {
        let directory = savedItemsBaseDirectoryURL

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch {
            statusText = "Unable to open save folder: \(error.localizedDescription)"
        }
    }

    func openLatestImage() {
        guard let item = latestImageItem else {
            statusText = "No image available to open."
            return
        }

        openImage(for: item)
    }

    func openImage(for item: ClipboardHistoryItem) {
        guard let imageData = item.payload.imageData else {
            statusText = "This item does not contain an image."
            return
        }

        do {
            let url = try temporaryFileURL(for: "AirCopy-Latest.png", data: imageData)
            NSWorkspace.shared.open(url)
            statusText = "Opened latest image."
        } catch {
            statusText = "Unable to open image: \(error.localizedDescription)"
        }
    }

    func trustPeer(_ deviceID: String) {
        trustedDeviceIDs.insert(deviceID)
        blockedDeviceIDs.remove(deviceID)
        autoSyncDisabledDeviceIDs.remove(deviceID)
        saveStringSet(trustedDeviceIDs, key: Self.trustedDeviceIDsKey)
        saveStringSet(blockedDeviceIDs, key: Self.blockedDeviceIDsKey)
        saveStringSet(autoSyncDisabledDeviceIDs, key: Self.autoSyncDisabledDeviceIDsKey)
        updateTrustState(for: deviceID, to: .trusted)
        inviteIfPossible(deviceID: deviceID)
        statusText = "Trusted \(peerStateByID[deviceID]?.displayName ?? "device")."
    }

    func blockPeer(_ deviceID: String) {
        blockedDeviceIDs.insert(deviceID)
        trustedDeviceIDs.remove(deviceID)
        autoSyncDisabledDeviceIDs.remove(deviceID)
        saveStringSet(blockedDeviceIDs, key: Self.blockedDeviceIDsKey)
        saveStringSet(trustedDeviceIDs, key: Self.trustedDeviceIDsKey)
        saveStringSet(autoSyncDisabledDeviceIDs, key: Self.autoSyncDisabledDeviceIDsKey)
        updateTrustState(for: deviceID, to: .blocked)

        if let peer = peerIDByDeviceID[deviceID] {
            session.cancelConnectPeer(peer)
        }

        statusText = "Blocked \(peerStateByID[deviceID]?.displayName ?? "device")."
    }

    func addFrontmostApplicationToExclusions() {
        let frontmost = Self.frontmostApplicationInfo()
        guard let bundleID = frontmost.bundleID else {
            statusText = "No frontmost app was detected."
            return
        }

        let name = frontmost.name ?? bundleID
        excludedAppMap[bundleID] = name
        persistExcludedApplications()
        statusText = "Excluded \(name) from sync."
    }

    func removeExcludedApplication(_ exclusion: AppExclusion) {
        excludedAppMap.removeValue(forKey: exclusion.bundleID)
        persistExcludedApplications()
        statusText = "Removed \(exclusion.appName) from exclusions."
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showSettings() {
        showMainWindow()
        settingsPresented = true
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

        statusText = "Searching for nearby Macs..."
    }

    private func stopServices() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()

        for id in peerStateByID.keys {
            peerStateByID[id]?.isConnected = false
            peerStateByID[id]?.isDiscovered = false
        }

        refreshPeerDevices()
        statusText = "Clipboard sync disabled."
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
                try? await Task.sleep(for: .seconds(60))
                await MainActor.run {
                    self?.updateEffectiveColorScheme()
                }
            }
        }
    }

    private func restartScreenshotImportMonitorIfNeeded() {
        screenshotImportTask?.cancel()
        screenshotImportTask = nil
        screenshotMonitorFolderPath = nil
        knownScreenshotFileSignatures.removeAll()

        guard importSystemScreenshotsEnabled else { return }

        seedKnownScreenshotFiles()

        screenshotImportTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(850))
                await MainActor.run {
                    self?.pollScreenshotFolder()
                }
            }
        }
    }

    private func seedKnownScreenshotFiles() {
        let folderURL = systemScreenshotFolderURL
        screenshotMonitorFolderPath = folderURL.path
        guard let candidates = screenshotCandidateFiles(in: folderURL) else {
            statusText = "Allow access to \(screenshotImportFolderDisplayPath) so AirCopy can import standard screenshots."
            return
        }

        knownScreenshotFileSignatures = Set(candidates.map(fileSignature(for:)))
    }

    private func pollScreenshotFolder() {
        let folderURL = systemScreenshotFolderURL

        if screenshotMonitorFolderPath != folderURL.path {
            screenshotMonitorFolderPath = folderURL.path
            guard let candidates = screenshotCandidateFiles(in: folderURL) else {
                statusText = "Allow access to \(screenshotImportFolderDisplayPath) so AirCopy can import standard screenshots."
                return
            }

            knownScreenshotFileSignatures = Set(candidates.map(fileSignature(for:)))
            return
        }

        guard let candidates = screenshotCandidateFiles(in: folderURL) else {
            statusText = "Allow access to \(screenshotImportFolderDisplayPath) so AirCopy can import standard screenshots."
            return
        }
        guard !candidates.isEmpty else { return }

        for url in candidates.sorted(by: screenshotFileSort) {
            let signature = fileSignature(for: url)
            guard !knownScreenshotFileSignatures.contains(signature) else { continue }

            if importScreenshotFile(at: url) {
                knownScreenshotFileSignatures.insert(signature)
            }
        }
    }

    private func screenshotFileSort(_ lhs: URL, _ rhs: URL) -> Bool {
        screenshotTimestamp(for: lhs) < screenshotTimestamp(for: rhs)
    }

    @discardableResult
    private func importScreenshotFile(at fileURL: URL) -> Bool {
        let age = Date().timeIntervalSince(screenshotTimestamp(for: fileURL))
        guard age >= 0.35 else { return false }
        guard let imageData = try? Data(contentsOf: fileURL), !imageData.isEmpty else { return false }
        guard NSImage(data: imageData) != nil else { return false }

        let payload = ClipboardPayload(
            imageData: imageData,
            sourceAppBundleID: nil,
            sourceAppName: "Screenshot"
        )

        pendingRemotePayload = nil
        lastKnownPayload = payload
        writePayloadToPasteboard(payload)

        let item = recordHistory(
            payload: payload,
            source: "Imported from macOS screenshot",
            senderName: localDeviceName,
            date: Date()
        )

        if !imageSyncEnabled {
            statusText = "Imported screenshot locally. Image sync is paused."
            return true
        }

        guard syncEnabled else {
            statusText = "Imported screenshot locally. Sync is off."
            return true
        }

        sendPayload(payload, toDeviceIDs: autoSyncPeers.map(\.id), historyItemID: item.id)
        return true
    }

    private func scheduleSyncExpirationTask() {
        syncExpirationTask?.cancel()

        guard let temporarySyncUntil else { return }

        syncExpirationTask = Task { [weak self] in
            let seconds = temporarySyncUntil.timeIntervalSinceNow

            if seconds > 0 {
                try? await Task.sleep(for: .seconds(seconds))
            }

            await MainActor.run {
                guard let self else { return }
                guard let until = self.temporarySyncUntil, until <= Date() else { return }
                self.syncEnabled = false
                self.temporarySyncUntil = nil
                self.statusText = "Temporary sync window ended."
            }
        }
    }

    private func pollClipboard() {
        let frontmost = Self.frontmostApplicationInfo()
        frontmostApplicationName = frontmost.name ?? "Unknown App"

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = changeCount

        guard let payload = Self.readClipboardPayload(
            from: pasteboard,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: frontmost.bundleID,
            sourceAppName: frontmost.name
        ) else {
            lastKnownPayload = nil
            return
        }

        if pendingRemotePayload == payload {
            pendingRemotePayload = nil
            lastKnownPayload = payload
            _ = recordHistory(
                payload: payload,
                source: "Received from a trusted Mac",
                senderName: "Peer",
                date: Date(),
                deliveredRemotely: true
            )
            return
        }

        guard payload != lastKnownPayload else { return }
        lastKnownPayload = payload

        guard !shouldSuppressSync(for: payload) else { return }

        let item = recordHistory(
            payload: payload,
            source: "Copied on this Mac",
            senderName: localDeviceName,
            date: Date()
        )

        if payload.kind == .image && !imageSyncEnabled {
            statusText = "Saved image locally. Image sync is paused."
            return
        }

        guard syncEnabled else {
            statusText = "Saved locally. Sync is off."
            return
        }

        sendPayload(payload, toDeviceIDs: autoSyncPeers.map(\.id), historyItemID: item.id)
    }

    private func sendPayload(
        _ payload: ClipboardPayload,
        toDeviceIDs targetDeviceIDs: [String],
        historyItemID: UUID?,
        sendOnly: Bool = false
    ) {
        let targets = targetDeviceIDs.compactMap { deviceID -> (String, PeerDeviceState, MCPeerID)? in
            guard let state = peerStateByID[deviceID], let peer = peerIDByDeviceID[deviceID] else { return nil }
            guard connectedDeviceIDs.contains(deviceID) || session.connectedPeers.contains(peer) else { return nil }
            return (deviceID, state, peer)
        }

        guard !targets.isEmpty else {
            statusText = sendOnly ? "No trusted connected device is available." : "Saved locally. Waiting for a trusted Mac."
            return
        }

        let message = ClipboardMessage(
            id: UUID(),
            senderID: deviceID,
            senderName: localDeviceName,
            payload: payload,
            sentAt: Date()
        )

        rememberMessageID(message.id)
        outboundMessageHistoryMap[message.id] = historyItemID

        let data: Data
        do {
            data = try JSONEncoder().encode(AirCopyWireMessage.clipboard(message))
        } catch {
            statusText = "Unable to prepare this clipboard item."
            return
        }

        if let historyItemID {
            markReceiptsPending(for: historyItemID, targets: targets.map { ($0.0, $0.1.displayName) })
        }

        for (deviceID, state, peer) in targets {
            do {
                try session.send(data, toPeers: [peer], with: .reliable)
                updatePeer(deviceID: deviceID) { peerState in
                    peerState.lastSyncAt = Date()
                    peerState.lastClipboardSummary = payload.title
                    peerState.lastReceiptState = .pending
                    peerState.lastReceiptText = "Sending \(payload.kind.title.lowercased())"
                }
            } catch {
                updatePeer(deviceID: deviceID) { peerState in
                    peerState.lastReceiptState = .failed
                    peerState.lastReceiptText = "Send failed"
                }
                if let historyItemID {
                    updateReceipt(
                        for: historyItemID,
                        deviceID: deviceID,
                        deviceName: state.displayName,
                        state: .failed,
                        date: Date()
                    )
                }
            }
        }

        refreshPeerDevices()
        let destinationSummary = targets.map { $0.1.displayName }.joined(separator: ", ")
        statusText = sendOnly
            ? "Sent \(payload.kind.title.lowercased()) to \(destinationSummary)."
            : "Synced \(payload.kind.title.lowercased()) to \(destinationSummary)."
    }

    private func applyRemoteClipboard(_ message: ClipboardMessage, fromPeer peer: MCPeerID) {
        guard message.senderID != deviceID else { return }
        guard !recentMessageSet.contains(message.id) else { return }

        rememberMessageID(message.id)

        if message.payload.kind == .image && !imageSyncEnabled {
            statusText = "Ignored image from \(message.senderName). Image sync is paused."
            return
        }

        pendingRemotePayload = message.payload
        lastKnownPayload = message.payload
        writePayloadToPasteboard(message.payload)
        _ = recordHistory(
            payload: message.payload,
            source: "Received from \(message.senderName)",
            senderName: message.senderName,
            date: message.sentAt,
            deliveredRemotely: true
        )

        if let senderDeviceID = peerDisplayNameToDeviceID[peer.displayName] {
            updatePeer(deviceID: senderDeviceID) { peerState in
                peerState.lastSyncAt = Date()
                peerState.lastClipboardSummary = message.payload.title
            }
        }

        sendReceipt(.clipboardUpdated, for: message, to: peer)
        switch saveReceivedPayloadToDiskIfNeeded(message.payload, date: message.sentAt) {
        case .saved(let summary):
            statusText = "Clipboard updated from \(message.senderName). \(summary)"
        case .failed(let summary):
            statusText = "Clipboard updated from \(message.senderName). \(summary)"
        case .skipped:
            statusText = "Clipboard updated from \(message.senderName)."
        }
    }

    private func handleReceipt(_ receipt: ClipboardReceipt) {
        guard let historyItemID = outboundMessageHistoryMap[receipt.messageID] else { return }

        let state: DeliveryState = receipt.kind == .clipboardUpdated ? .clipboardUpdated : .delivered
        updateReceipt(
            for: historyItemID,
            deviceID: receipt.recipientID,
            deviceName: receipt.recipientName,
            state: state,
            date: receipt.sentAt
        )

        updatePeer(deviceID: receipt.recipientID) { peerState in
            peerState.lastSyncAt = receipt.sentAt
            peerState.lastReceiptState = state
            peerState.lastReceiptText = state == .clipboardUpdated ? "Clipboard updated" : "Delivered"
        }

        refreshPeerDevices()
        statusText = state == .clipboardUpdated
            ? "\(receipt.recipientName) updated its clipboard."
            : "Delivered to \(receipt.recipientName)."
    }

    private func sendReceipt(_ kind: ClipboardReceiptKind, for message: ClipboardMessage, to peer: MCPeerID) {
        let receipt = ClipboardReceipt(
            messageID: message.id,
            recipientID: deviceID,
            recipientName: localDeviceName,
            kind: kind,
            sentAt: Date()
        )

        do {
            let data = try JSONEncoder().encode(AirCopyWireMessage.receipt(receipt))
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            statusText = "Failed to send receipt to \(message.senderName)."
        }
    }

    private func writePayloadToPasteboard(_ payload: ClipboardPayload) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch payload.kind {
        case .text, .code:
            pasteboard.setString(payload.text ?? "", forType: .string)
        case .link, .browserTab:
            if let urlString = payload.urlString, let url = URL(string: urlString) {
                _ = pasteboard.writeObjects([url as NSURL])
                pasteboard.setString(urlString, forType: .string)

                if let linkTitle = payload.linkTitle {
                    pasteboard.setString(linkTitle, forType: NSPasteboard.PasteboardType("public.url-name"))
                }
            } else if let text = payload.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = payload.imageData, let image = NSImage(data: data) {
                if !pasteboard.writeObjects([image]) {
                    pasteboard.setData(data, forType: .png)
                }
            }
        case .file, .folder:
            writeAttachments(payload.attachments, to: pasteboard)
        }

        lastObservedChangeCount = pasteboard.changeCount
    }

    private func writeAttachments(_ attachments: [ClipboardAttachment], to pasteboard: NSPasteboard) {
        let urls = attachments.compactMap { attachment in
            if let inlineData = attachment.inlineData, !attachment.isDirectory {
                return try? temporaryFileURL(for: attachment.name, data: inlineData)
            }

            let url = URL(fileURLWithPath: attachment.originalPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        if !urls.isEmpty {
            _ = pasteboard.writeObjects(urls as [NSURL])
        }

        let pathListing = attachments.map(\.originalPath).joined(separator: "\n")
        if !pathListing.isEmpty {
            pasteboard.setString(pathListing, forType: .string)
        }
    }

    private func recordHistory(
        payload: ClipboardPayload,
        source: String,
        senderName: String,
        date: Date,
        deliveredRemotely: Bool = false
    ) -> ClipboardHistoryItem {
        let existing = clipboardHistory.first(where: { $0.fingerprint == payload.fingerprint })

        let item = ClipboardHistoryItem(
            id: existing?.id ?? UUID(),
            payload: payload,
            source: source,
            senderName: senderName,
            date: date,
            isPinned: existing?.isPinned ?? pinnedFingerprints.contains(payload.fingerprint),
            isFavorite: existing?.isFavorite ?? favoriteFingerprints.contains(payload.fingerprint),
            deviceReceipts: existing?.deviceReceipts ?? [],
            lastSyncAt: deliveredRemotely ? date : existing?.lastSyncAt,
            wasDeliveredRemotely: deliveredRemotely || (existing?.wasDeliveredRemotely ?? false)
        )

        clipboardHistory.removeAll { $0.fingerprint == payload.fingerprint }
        clipboardHistory.append(item)
        sortAndTrimHistory()
        return item
    }

    private func updateHistoryItem(id: UUID, source: String, senderName: String, date: Date) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == id }) else { return }
        clipboardHistory[index].source = source
        clipboardHistory[index].senderName = senderName
        clipboardHistory[index].date = date
        sortAndTrimHistory()
    }

    private func sortAndTrimHistory() {
        clipboardHistory.sort(by: historySort)

        if clipboardHistory.count > maxHistoryItems {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryItems))
        }
    }

    private func historySort(_ lhs: ClipboardHistoryItem, _ rhs: ClipboardHistoryItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }

        return lhs.date > rhs.date
    }

    private func markReceiptsPending(for historyItemID: UUID, targets: [(String, String)]) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == historyItemID }) else { return }

        for (deviceID, deviceName) in targets {
            updateReceipt(
                for: historyItemID,
                deviceID: deviceID,
                deviceName: deviceName,
                state: .pending,
                date: Date()
            )
        }

        clipboardHistory[index].lastSyncAt = Date()
    }

    private func updateReceipt(
        for historyItemID: UUID,
        deviceID: String,
        deviceName: String,
        state: DeliveryState,
        date: Date
    ) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == historyItemID }) else { return }

        var item = clipboardHistory[index]

        if let existingIndex = item.deviceReceipts.firstIndex(where: { $0.deviceID == deviceID }) {
            item.deviceReceipts[existingIndex].state = state
            item.deviceReceipts[existingIndex].date = date
            item.deviceReceipts[existingIndex].deviceName = deviceName
        } else {
            item.deviceReceipts.append(DeviceReceipt(deviceID: deviceID, deviceName: deviceName, state: state, date: date))
        }

        item.lastSyncAt = date
        clipboardHistory[index] = item
        sortAndTrimHistory()
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
        guard clipboardHistory.contains(where: { $0.id == id }) else { return }

        recentlyCopiedHistoryItemID = id
        clearCopiedStateTask?.cancel()
        clearCopiedStateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                guard self?.recentlyCopiedHistoryItemID == id else { return }
                self?.recentlyCopiedHistoryItemID = nil
            }
        }
    }

    private func rememberMessageID(_ id: UUID) {
        recentMessageIDs.append(id)
        recentMessageSet.insert(id)

        if recentMessageIDs.count > 512 {
            let removed = recentMessageIDs.removeFirst()
            recentMessageSet.remove(removed)
        }
    }

    private func inviteIfPossible(deviceID: String) {
        guard trustedDeviceIDs.contains(deviceID) else { return }
        guard let peer = peerIDByDeviceID[deviceID] else { return }
        guard !session.connectedPeers.contains(peer) else { return }
        guard shouldAttemptInvite(to: deviceID) else { return }

        let context = PeerInvitationContext(deviceID: self.deviceID, deviceName: localDeviceName)
        let contextData = try? JSONEncoder().encode(context)
        lastInviteAttemptByDeviceID[deviceID] = Date()
        browser?.invitePeer(peer, to: session, withContext: contextData, timeout: 10)
    }

    private func shouldAttemptInvite(to deviceID: String) -> Bool {
        guard let lastAttemptAt = lastInviteAttemptByDeviceID[deviceID] else {
            return true
        }

        return Date().timeIntervalSince(lastAttemptAt) >= inviteRetryInterval
    }

    private func updatePeer(deviceID: String, mutate: (inout PeerDeviceState) -> Void) {
        guard var peer = peerStateByID[deviceID] else { return }
        mutate(&peer)
        peerStateByID[deviceID] = peer
    }

    private func updateTrustState(for deviceID: String, to trustState: PeerTrustState) {
        updatePeer(deviceID: deviceID) { peer in
            peer.trustState = trustState
            peer.isAutoSyncEnabled = autoSyncEnabledState(for: deviceID, trustState: trustState)
        }
        refreshPeerDevices()
    }

    private func enableAutoSyncForAllTrustedDevices() {
        autoSyncDisabledDeviceIDs.subtract(trustedDeviceIDs)
        saveStringSet(autoSyncDisabledDeviceIDs, key: Self.autoSyncDisabledDeviceIDsKey)

        for deviceID in trustedDeviceIDs {
            updatePeer(deviceID: deviceID) { peer in
                peer.isAutoSyncEnabled = true
            }
        }

        refreshPeerDevices()
    }

    private func refreshPeerDevices() {
        reconcileConnectionStates()
        peerDevices = peerStateByID.values.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected {
                return lhs.isConnected && !rhs.isConnected
            }

            if lhs.trustState != rhs.trustState {
                return lhs.trustState == .trusted
            }

            if lhs.isDiscovered != rhs.isDiscovered {
                return lhs.isDiscovered && !rhs.isDiscovered
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var connectedDeviceIDs: Set<String> {
        Set(
            session.connectedPeers.map { peer in
                peerDisplayNameToDeviceID[peer.displayName] ?? peer.displayName
            }
        )
    }

    private func reconcileConnectionStates() {
        let connectedIDs = connectedDeviceIDs

        for id in peerStateByID.keys {
            peerStateByID[id]?.isConnected = connectedIDs.contains(id)
        }
    }

    private func upsertPeer(
        displayName: String,
        deviceID providedDeviceID: String?,
        discovered: Bool? = nil,
        connected: Bool? = nil
    ) -> String {
        let resolvedID: String

        if let providedDeviceID, !providedDeviceID.isEmpty {
            resolvedID = providedDeviceID
            peerDisplayNameToDeviceID[displayName] = providedDeviceID

            if let temporaryPeer = peerStateByID.removeValue(forKey: displayName), peerStateByID[providedDeviceID] == nil {
                var migrated = temporaryPeer
                migrated = PeerDeviceState(
                    id: providedDeviceID,
                    displayName: displayName,
                    trustState: trustState(for: providedDeviceID),
                    isDiscovered: discovered ?? temporaryPeer.isDiscovered,
                    isConnected: connected ?? temporaryPeer.isConnected,
                    isAutoSyncEnabled: autoSyncEnabledState(for: providedDeviceID, trustState: trustState(for: providedDeviceID)),
                    lastSeenAt: Date(),
                    lastSyncAt: temporaryPeer.lastSyncAt,
                    lastReceiptState: temporaryPeer.lastReceiptState,
                    lastReceiptText: temporaryPeer.lastReceiptText,
                    lastClipboardSummary: temporaryPeer.lastClipboardSummary,
                    encryptedTransport: true
                )
                peerStateByID[providedDeviceID] = migrated
            }
        } else {
            resolvedID = peerDisplayNameToDeviceID[displayName] ?? displayName
        }

        let current = peerStateByID[resolvedID]
        let peer = PeerDeviceState(
            id: resolvedID,
            displayName: displayName,
            trustState: trustState(for: resolvedID),
            isDiscovered: discovered ?? current?.isDiscovered ?? false,
            isConnected: connected ?? current?.isConnected ?? false,
            isAutoSyncEnabled: autoSyncEnabledState(
                for: resolvedID,
                trustState: trustState(for: resolvedID)
            ),
            lastSeenAt: Date(),
            lastSyncAt: current?.lastSyncAt,
            lastReceiptState: current?.lastReceiptState,
            lastReceiptText: current?.lastReceiptText,
            lastClipboardSummary: current?.lastClipboardSummary,
            encryptedTransport: true
        )

        peerStateByID[resolvedID] = peer
        refreshPeerDevices()
        return resolvedID
    }

    private func trustState(for deviceID: String) -> PeerTrustState {
        if blockedDeviceIDs.contains(deviceID) {
            return .blocked
        }

        if trustedDeviceIDs.contains(deviceID) {
            return .trusted
        }

        return requireDeviceApproval ? .pending : .trusted
    }

    private func autoSyncEnabledState(for deviceID: String, trustState: PeerTrustState? = nil) -> Bool {
        let resolvedTrustState = trustState ?? self.trustState(for: deviceID)
        guard resolvedTrustState == .trusted else { return false }
        return !autoSyncDisabledDeviceIDs.contains(deviceID)
    }

    private var systemScreenshotFolderURL: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    private var savedItemsBaseDirectoryURL: URL {
        let trimmedPath = savedItemsBaseDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = trimmedPath.isEmpty ? Self.defaultSavedItemsBaseDirectory.path : trimmedPath
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    private static var defaultSavedItemsBaseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AirCopy", isDirectory: true)
    }

    private func saveReceivedPayloadToDiskIfNeeded(_ payload: ClipboardPayload, date: Date) -> SaveReceivedPayloadResult {
        guard saveReceivedItemsToDiskEnabled else { return .skipped }

        do {
            switch payload.kind {
            case .image:
                guard saveReceivedImagesToDisk, let imageData = payload.imageData else { return .skipped }
                let folder = try subdirectoryURL(named: "Images")
                let stem = fileStem(from: payload.title, fallback: "Image-\(timestampString(from: date))")
                let destination = uniqueFileURL(in: folder, preferredStem: stem, pathExtension: "png")
                try imageData.write(to: destination, options: .atomic)
                return .saved("Saved to Images.")

            case .text, .code, .link, .browserTab:
                guard saveReceivedTextToDisk else { return .skipped }
                let contents = payload.plainTextRepresentation
                guard let data = contents.data(using: .utf8), !data.isEmpty else { return .skipped }
                let folder = try subdirectoryURL(named: "Text")
                let stem = fileStem(from: payload.title, fallback: "Text-\(timestampString(from: date))")
                let destination = uniqueFileURL(
                    in: folder,
                    preferredStem: stem,
                    pathExtension: textFileExtension(for: payload)
                )
                try data.write(to: destination, options: .atomic)
                return .saved("Saved to Text.")

            case .file, .folder:
                guard saveReceivedFilesToDisk else { return .skipped }
                guard let summary = try saveAttachmentsToDisk(payload.attachments) else {
                    return .skipped
                }
                return .saved(summary)
            }
        } catch {
            return .failed("Could not save a copy: \(error.localizedDescription)")
        }
    }

    private func saveAttachmentsToDisk(_ attachments: [ClipboardAttachment]) throws -> String? {
        guard !attachments.isEmpty else { return nil }

        let folder = try subdirectoryURL(named: "Files")
        var savedCount = 0
        var skippedCount = 0

        for attachment in attachments {
            if try saveAttachment(attachment, to: folder) {
                savedCount += 1
            } else {
                skippedCount += 1
            }
        }

        if savedCount == 0, skippedCount > 0 {
            return "Some file references could not be saved."
        }

        if skippedCount > 0 {
            return "Saved \(savedCount) file\(savedCount == 1 ? "" : "s"). Some references were skipped."
        }

        return savedCount == 1 ? "Saved to Files." : "Saved \(savedCount) files to Files."
    }

    private func saveAttachment(_ attachment: ClipboardAttachment, to folder: URL) throws -> Bool {
        if let inlineData = attachment.inlineData, !attachment.isDirectory {
            let destination = uniqueFileURL(
                in: folder,
                preferredStem: attachmentFileStem(for: attachment),
                pathExtension: fileExtension(for: attachment)
            )
            try inlineData.write(to: destination, options: .atomic)
            return true
        }

        let sourceURL = URL(fileURLWithPath: attachment.originalPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }

        let destination = uniqueFileURL(
            in: folder,
            preferredStem: attachment.isDirectory
                ? attachmentDirectoryStem(for: attachment)
                : attachmentFileStem(for: attachment),
            pathExtension: attachment.isDirectory ? nil : fileExtension(for: attachment)
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return true
    }

    private func subdirectoryURL(named folderName: String) throws -> URL {
        let directory = savedItemsBaseDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func uniqueFileURL(in directory: URL, preferredStem: String, pathExtension: String?) -> URL {
        let stem = preferredStem.isEmpty ? "AirCopy" : preferredStem
        let sanitizedExtension = (pathExtension ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var candidate = directory.appendingPathComponent(stem)
        if !sanitizedExtension.isEmpty {
            candidate.appendPathExtension(sanitizedExtension)
        }

        guard !FileManager.default.fileExists(atPath: candidate.path) else {
            var suffix = 2
            while true {
                var numbered = directory.appendingPathComponent("\(stem)-\(suffix)")
                if !sanitizedExtension.isEmpty {
                    numbered.appendPathExtension(sanitizedExtension)
                }

                if !FileManager.default.fileExists(atPath: numbered.path) {
                    return numbered
                }

                suffix += 1
            }
        }

        return candidate
    }

    private func fileStem(from rawValue: String, fallback: String) -> String {
        let cleaned = rawValue
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = cleaned.isEmpty ? fallback : cleaned
        return String(base.prefix(60))
    }

    private func fileExtension(for attachment: ClipboardAttachment) -> String? {
        if !attachment.fileExtension.isEmpty {
            return attachment.fileExtension
        }

        if let typeIdentifier = attachment.typeIdentifier,
           let contentType = UTType(typeIdentifier),
           let preferredExtension = contentType.preferredFilenameExtension {
            return preferredExtension
        }

        return nil
    }

    private func attachmentFileStem(for attachment: ClipboardAttachment) -> String {
        let rawName = URL(fileURLWithPath: attachment.name).deletingPathExtension().lastPathComponent
        return fileStem(from: rawName, fallback: "File")
    }

    private func attachmentDirectoryStem(for attachment: ClipboardAttachment) -> String {
        fileStem(from: attachment.name, fallback: "Folder")
    }

    private func textFileExtension(for payload: ClipboardPayload) -> String {
        guard payload.kind == .code else { return "txt" }

        switch payload.languageHint?.lowercased() {
        case "swift":
            return "swift"
        case "javascript":
            return "js"
        case "html":
            return "html"
        case "css":
            return "css"
        case "sql":
            return "sql"
        case "json":
            return "json"
        case "bash":
            return "sh"
        default:
            return "txt"
        }
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    private func screenshotCandidateFiles(in folderURL: URL) -> [URL]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentTypeKey,
                .contentModificationDateKey,
                .creationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  values.isRegularFile == true else {
                return false
            }

            let contentTypeIsImage = values.contentType?.conforms(to: .image) == true
            let extensionIsImage = Self.imageFileExtensions.contains(url.pathExtension.lowercased())
            guard contentTypeIsImage || extensionIsImage else { return false }
            return Self.looksLikeScreenshotFilename(url.lastPathComponent)
        }
    }

    private func screenshotTimestamp(for fileURL: URL) -> Date {
        let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate ?? .distantPast
    }

    private func fileSignature(for fileURL: URL) -> String {
        let timestamp = screenshotTimestamp(for: fileURL)
        return "\(fileURL.path)#\(timestamp.timeIntervalSince1970)"
    }

    private static func looksLikeScreenshotFilename(_ filename: String) -> Bool {
        let normalized = filename
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let markers = [
            "screenshot",
            "screen shot",
            "screen-shot",
            "screen_shot",
            "screencapture",
            "screen capture",
            "captura de pantalla",
            "captura de tela",
            "capture d'ecran",
            "capture decran"
        ]

        return markers.contains { normalized.contains($0) }
    }

    private func shouldSuppressSync(for payload: ClipboardPayload) -> Bool {
        guard let bundleID = payload.sourceAppBundleID else { return false }

        let lowercasedBundleID = bundleID.lowercased()
        if protectedPasswordManagerBundleIDs.contains(lowercasedBundleID) || lowercasedBundleID.contains("1password") || lowercasedBundleID.contains("bitwarden") {
            statusText = "Skipped clipboard from \(payload.sourceAppName ?? bundleID)."
            return true
        }

        if let name = excludedAppMap[bundleID] {
            statusText = "Skipped clipboard from excluded app \(name)."
            return true
        }

        return false
    }

    private func persistExcludedApplications() {
        if let data = try? JSONEncoder().encode(excludedAppMap) {
            UserDefaults.standard.set(data, forKey: Self.excludedAppsKey)
        }

        excludedApplications = excludedAppMap
            .map { AppExclusion(bundleID: $0.key, appName: $0.value) }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func saveStringSet(_ set: Set<String>, key: String) {
        UserDefaults.standard.set(Array(set).sorted(), forKey: key)
    }

    private static func loadStringSet(forKey key: String) -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(values)
    }

    private static func loadStringDictionary(forKey key: String) -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return map
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

    private static func frontmostApplicationInfo() -> (bundleID: String?, name: String?) {
        let application = NSWorkspace.shared.frontmostApplication
        return (application?.bundleIdentifier, application?.localizedName)
    }

    private static func readClipboardPayload(
        from pasteboard: NSPasteboard,
        maxInlineAttachmentBytes: Int64,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        if let imagePayload = imagePayload(
            from: pasteboard,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return imagePayload
        }

        if let attachmentPayload = attachmentPayload(
            from: pasteboard,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return attachmentPayload
        }

        if let urlPayload = urlPayload(
            from: pasteboard,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return urlPayload
        }

        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if looksLikeURL(trimmed) {
            return ClipboardPayload(
                urlString: trimmed,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        if let language = detectCodeLanguage(in: text) {
            return ClipboardPayload(
                code: text,
                languageHint: language,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        return ClipboardPayload(
            text: text,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func imagePayload(
        from pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        guard containsDirectImagePayload(in: pasteboard),
              let imageData = pngData(from: pasteboard),
              !imageData.isEmpty else {
            return nil
        }

        return ClipboardPayload(
            imageData: imageData,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func containsDirectImagePayload(in pasteboard: NSPasteboard) -> Bool {
        if let types = pasteboard.types,
           types.contains(where: { $0 == .png || $0 == .tiff }) {
            return true
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           !images.isEmpty {
            return true
        }

        return false
    }

    private static func attachmentPayload(
        from pasteboard: NSPasteboard,
        maxInlineAttachmentBytes: Int64,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return nil }
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return nil }

        let attachments = fileURLs.compactMap { fileURL -> ClipboardAttachment? in
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .nameKey,
                    .contentTypeKey
                ])

                let isDirectory = values.isDirectory ?? false
                let fileSize = values.fileSize.map(Int64.init)
                let inlineData: Data?

                if !isDirectory, let fileSize, fileSize <= maxInlineAttachmentBytes {
                    inlineData = try? Data(contentsOf: fileURL)
                } else {
                    inlineData = nil
                }

                return ClipboardAttachment(
                    name: values.name ?? fileURL.lastPathComponent,
                    originalPath: fileURL.path,
                    isDirectory: isDirectory,
                    byteCount: fileSize,
                    typeIdentifier: values.contentType?.identifier,
                    inlineData: inlineData
                )
            } catch {
                return ClipboardAttachment(
                    name: fileURL.lastPathComponent,
                    originalPath: fileURL.path,
                    isDirectory: false
                )
            }
        }

        guard !attachments.isEmpty else { return nil }
        return ClipboardPayload(
            attachments: attachments,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func urlPayload(
        from pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        let urlNameType = NSPasteboard.PasteboardType("public.url-name")

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first(where: { !$0.isFileURL }) {
            let linkTitle = pasteboard.string(forType: urlNameType)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let browserTab = (linkTitle?.isEmpty == false) && linkTitle != url.absoluteString
            return ClipboardPayload(
                urlString: url.absoluteString,
                linkTitle: linkTitle,
                browserTab: browserTab,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        return nil
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        guard let url = URL(string: text) else { return false }
        return url.scheme?.hasPrefix("http") == true && url.host(percentEncoded: false) != nil
    }

    private static func detectCodeLanguage(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineCount = trimmed.split(separator: "\n", omittingEmptySubsequences: false).count

        if let data = trimmed.data(using: .utf8),
           (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return "json"
        }

        guard lineCount > 1 || trimmed.contains("{") || trimmed.contains(";") else { return nil }

        let lowercased = trimmed.lowercased()

        if lowercased.contains("import swiftui") || lowercased.contains("func ") || lowercased.contains("struct ") {
            return "swift"
        }

        if lowercased.contains("const ") || lowercased.contains("function ") || lowercased.contains("=>") {
            return "javascript"
        }

        if lowercased.hasPrefix("#!/bin/") || lowercased.contains("echo ") || lowercased.contains("export ") {
            return "bash"
        }

        if lowercased.contains("<html") || lowercased.contains("<div") || lowercased.contains("</") {
            return "html"
        }

        if lowercased.contains("{") && lowercased.contains(":") && lowercased.contains(";") {
            return "css"
        }

        if lowercased.contains("select ") || lowercased.contains(" from ") {
            return "sql"
        }

        if lineCount > 1 && (trimmed.contains("{") || trimmed.contains("}") || trimmed.contains("let ") || trimmed.contains("=")) {
            return "code"
        }

        return nil
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

    private func temporaryFileURL(for filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aircopy-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeName = filename.isEmpty ? UUID().uuidString : filename
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try data.write(to: url, options: .atomic)
        return url
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
        let handlerBox = InvitationHandlerBox(invitationHandler)
        let peerBox = PeerIDBox(peerID)
        let peerName = peerID.displayName
        let contextValue = try? JSONDecoder().decode(PeerInvitationContext.self, from: context ?? Data())

        Task { @MainActor [weak self] in
            guard let self else {
                handlerBox.handler(false, nil)
                return
            }

            let resolvedID = self.upsertPeer(
                displayName: peerName,
                deviceID: contextValue?.deviceID,
                discovered: true,
                connected: false
            )

            self.peerIDByDeviceID[resolvedID] = peerBox.peerID
            let trustState = self.trustState(for: resolvedID)

            guard trustState == .trusted else {
                self.statusText = trustState == .pending
                    ? "Approval required for \(peerName)."
                    : "Blocked invitation from \(peerName)."
                handlerBox.handler(false, nil)
                return
            }

            self.statusText = "Connecting to \(peerName)..."
            handlerBox.handler(true, self.session)
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
        let peerBox = PeerIDBox(peerID)
        let peerName = peerID.displayName
        let discoveredDeviceID = info?["deviceID"]

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard peerName != self.peerID.displayName else { return }

            let resolvedID = self.upsertPeer(
                displayName: peerName,
                deviceID: discoveredDeviceID,
                discovered: true,
                connected: false
            )
            self.peerIDByDeviceID[resolvedID] = peerBox.peerID

            guard self.trustState(for: resolvedID) == .trusted else {
                self.statusText = "Found \(peerName). Approval needed before connecting."
                return
            }

            self.statusText = "Found \(peerName). Connecting..."
            self.inviteIfPossible(deviceID: resolvedID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerName = peerID.displayName

        Task { @MainActor [weak self] in
            guard let self else { return }

            let resolvedID = self.peerDisplayNameToDeviceID[peerName] ?? peerName
            self.updatePeer(deviceID: resolvedID) { peer in
                peer.isDiscovered = false
            }
            self.refreshPeerDevices()
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

            let resolvedID = self.peerDisplayNameToDeviceID[peerName] ?? peerName
            let trustState = self.trustState(for: resolvedID)

            _ = self.upsertPeer(
                displayName: peerName,
                deviceID: self.peerDisplayNameToDeviceID[peerName],
                discovered: state != .notConnected,
                connected: state == .connected
            )

            switch state {
            case .connected:
                self.statusText = "Connected to \(peerName)."

                if trustState == .trusted,
                   self.isAutoSyncEnabled(for: resolvedID),
                   let payload = self.lastKnownPayload,
                   self.syncEnabled {
                    self.sendPayload(payload, toDeviceIDs: [resolvedID], historyItemID: self.latestClipboardItem?.id)
                }
            case .connecting:
                self.statusText = "Connecting to \(peerName)..."
            case .notConnected:
                self.updatePeer(deviceID: resolvedID) { peer in
                    peer.isConnected = false
                }
                self.refreshPeerDevices()

                if trustState == .trusted,
                   self.peerStateByID[resolvedID]?.isDiscovered == true {
                    self.statusText = "Reconnecting to \(peerName)..."
                    self.inviteIfPossible(deviceID: resolvedID)
                    return
                }

                self.statusText = self.connectedPeerCount == 0 ? "Waiting for a trusted nearby Mac." : "Connected to \(self.connectedPeerCount) Mac(s)."
            @unknown default:
                self.statusText = "Peer state changed."
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peerBox = PeerIDBox(peerID)
        let peerName = peerID.displayName

        do {
            let wireMessage = try JSONDecoder().decode(AirCopyWireMessage.self, from: data)

            Task { @MainActor [weak self] in
                guard let self else { return }

                switch wireMessage.kind {
                case .clipboard:
                    if let message = wireMessage.clipboard {
                        self.applyRemoteClipboard(message, fromPeer: peerBox.peerID)
                    }
                case .receipt:
                    if let receipt = wireMessage.receipt {
                        self.handleReceipt(receipt)
                    }
                }
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.statusText = "Received invalid data from \(peerName)."
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
