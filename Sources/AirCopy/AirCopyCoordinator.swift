import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit.ps
import MultipeerConnectivity
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AirCopyCoordinator: NSObject, ObservableObject {
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

    @Published var applyAppPoliciesToIncomingItems = true {
        didSet {
            UserDefaults.standard.set(applyAppPoliciesToIncomingItems, forKey: Self.applyAppPoliciesToIncomingItemsKey)
            statusText = applyAppPoliciesToIncomingItems
                ? "Incoming clips will respect excluded-app rules."
                : "Incoming clips will ignore custom excluded-app rules."
        }
    }

    @Published var blockPasswordManagerClips = true {
        didSet {
            UserDefaults.standard.set(blockPasswordManagerClips, forKey: Self.blockPasswordManagerClipsKey)
            statusText = blockPasswordManagerClips
                ? "Password manager clips are blocked from team sync."
                : "Password manager clips can sync when sent."
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
    /// The color scheme to force on the window. `nil` means "follow the system
    /// appearance" (the System / automatic option), letting SwiftUI inherit and
    /// react to macOS Appearance changes on its own.
    @Published private(set) var effectiveColorScheme: ColorScheme?
    @Published private(set) var appIconImage: NSImage?
    @Published private(set) var imageThumbnailByFingerprint: [String: NSImage] = [:]
    @Published private(set) var protectedPasswordManagerApplications: [ProtectedAppRule] = AppSourcePrivacyPolicy.protectedPasswordManagerApplications
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
    private static let historyLimitKey = "ac.settings.historyLimit"
    private static let soundEnabledKey = "ac.settings.soundOnSync"
    @Published var historyLimit: Int = {
        let stored = UserDefaults.standard.integer(forKey: AirCopyCoordinator.historyLimitKey)
        return stored == 0 ? 50 : stored
    }() {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: Self.historyLimitKey)
            if historyLimit != oldValue { sortAndTrimHistory() }
        }
    }
    @Published var soundEnabled: Bool = UserDefaults.standard.object(forKey: AirCopyCoordinator.soundEnabledKey) as? Bool ?? false {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundEnabledKey) }
    }
    private static let maxImageBytesKey = "ac.settings.maxImageBytes"
    private static let clearOnQuitKey = "ac.settings.clearHistoryOnQuit"
    private static let pauseOnBatteryKey = "ac.settings.pauseOnBattery"
    private static let autoSyncNewDevicesKey = "ac.settings.autoSyncNewDevices"

    /// Largest image clip (in bytes) that will be synced. 0 == unlimited.
    @Published var maxImageBytes: Int = (UserDefaults.standard.object(forKey: AirCopyCoordinator.maxImageBytesKey) as? Int) ?? (25 * 1024 * 1024) {
        didSet { UserDefaults.standard.set(maxImageBytes, forKey: Self.maxImageBytesKey) }
    }
    /// Forget clipboard history when AirCopy quits.
    @Published var clearHistoryOnQuit: Bool = UserDefaults.standard.bool(forKey: AirCopyCoordinator.clearOnQuitKey) {
        didSet { UserDefaults.standard.set(clearHistoryOnQuit, forKey: Self.clearOnQuitKey) }
    }
    /// Pause syncing while running on battery power.
    @Published var pauseOnBattery: Bool = UserDefaults.standard.bool(forKey: AirCopyCoordinator.pauseOnBatteryKey) {
        didSet {
            UserDefaults.standard.set(pauseOnBattery, forKey: Self.pauseOnBatteryKey)
            updatePowerMonitoring()
        }
    }
    /// Default a newly trusted Mac to auto-sync (vs. requiring you to enable it).
    @Published var autoSyncNewDevices: Bool = (UserDefaults.standard.object(forKey: AirCopyCoordinator.autoSyncNewDevicesKey) as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoSyncNewDevices, forKey: Self.autoSyncNewDevicesKey) }
    }
    /// True while syncing is suspended because the Mac is on battery.
    @Published private(set) var isPausedForBattery = false
    /// Result string from the most recent "Check for updates".
    @Published var updateCheckStatus: String?

    private var powerRunLoopSource: CFRunLoopSource?
    private var historyPersistTask: Task<Void, Never>?
    private let hotkeyManager = GlobalHotkeyManager()
    @Published private(set) var hotkeyBindings: [String: HotkeyBinding] = [:]
    private var maxHistoryItems: Int { historyLimit }
    private let maxInlineAttachmentBytes: Int64 = 8 * 1024 * 1024
    private let inviteRetryInterval: TimeInterval = 3
    private let pendingConnectionTimeout: TimeInterval = 10
    private let lostPeerGraceInterval: TimeInterval = 5
    private let connectivityHeartbeatInterval: Duration = .seconds(12)
    private let connectivityWatchdogInterval: Duration = .seconds(6)
    private let stalledConnectivityResetInterval: TimeInterval = 12
    private let minimumConnectivityResetSpacing: TimeInterval = 10

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerIDByDeviceID: [String: MCPeerID] = [:]
    private var deviceIDByPeerID: [MCPeerID: String] = [:]
    private var peerDisplayNameToDeviceID: [String: String] = [:]
    private var peerStateByID: [String: PeerDeviceState] = [:]
    private var lastInviteAttemptByDeviceID: [String: Date] = [:]
    private var pendingConnectionAttemptAtByDeviceID: [String: Date] = [:]
    private var deviceTrustStore: DeviceTrustStore
    private var pinnedFingerprints: Set<String>
    private var favoriteFingerprints: Set<String>
    private var excludedAppMap: [String: String]
    private var recentMessageIDs: [UUID] = []
    private var recentMessageSet = Set<UUID>()
    private var outboundMessageHistoryMap: [UUID: UUID] = [:]
    private var clipboardTask: Task<Void, Never>?
    private var connectivityHeartbeatTask: Task<Void, Never>?
    private var connectivityWatchdogTask: Task<Void, Never>?
    private var lostPeerTasksByDeviceID: [String: Task<Void, Never>] = [:]
    private var syncExpirationTask: Task<Void, Never>?
    private var thumbnailTasksByFingerprint: [String: Task<Void, Never>] = [:]
    private var clearCopiedStateTask: Task<Void, Never>?
    private var lastObservedChangeCount: Int
    private var lastKnownPayload: ClipboardPayload?
    private var pendingRemotePayload: ClipboardPayload?
    private var sensitiveContentApproval: SensitiveContentApproval?
    private var lastConnectivityEventAt = Date()
    private var lastConnectivityResetAt: Date?
    private var isPreparingForTermination = false

    private static let appearancePreferenceKey = "appearance-preference"
    private static let imageSyncEnabledKey = "image-sync-enabled"
    private static let saveReceivedItemsToDiskEnabledKey = "save-received-items-to-disk-enabled"
    private static let saveReceivedImagesToDiskKey = "save-received-images-to-disk"
    private static let saveReceivedTextToDiskKey = "save-received-text-to-disk"
    private static let saveReceivedFilesToDiskKey = "save-received-files-to-disk"
    private static let savedItemsBaseDirectoryPathKey = "saved-items-base-directory-path"
    private static let temporarySyncUntilKey = "temporary-sync-until"
    private static let pinnedFingerprintsKey = "pinned-fingerprints"
    private static let favoriteFingerprintsKey = "favorite-fingerprints"
    private static let excludedAppsKey = "excluded-app-map"
    private static let requireDeviceApprovalKey = "require-device-approval"
    private static let applyAppPoliciesToIncomingItemsKey = "apply-app-policies-to-incoming-items"
    private static let blockPasswordManagerClipsKey = "block-password-manager-clips"

    override init() {
        let hostName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = hostName?.isEmpty == false ? hostName! : "This Mac"
        let defaults = UserDefaults.standard
        let storedAppearance = defaults.string(forKey: Self.appearancePreferenceKey)
        let appearance = AppearancePreference(rawValue: storedAppearance ?? "") ?? .automatic
        let frontmost = MacSystemServices.frontmostApplicationInfo()

        self.localDeviceName = resolvedName
        self.appearancePreference = appearance
        self.deviceID = Self.loadOrCreateDeviceID()
        self.peerID = MCPeerID(displayName: Self.sanitizedPeerName(from: resolvedName))
        self.imageSyncEnabled = defaults.object(forKey: Self.imageSyncEnabledKey) as? Bool ?? true
        self.saveReceivedItemsToDiskEnabled = defaults.object(forKey: Self.saveReceivedItemsToDiskEnabledKey) as? Bool ?? false
        self.saveReceivedImagesToDisk = defaults.object(forKey: Self.saveReceivedImagesToDiskKey) as? Bool ?? true
        self.saveReceivedTextToDisk = defaults.object(forKey: Self.saveReceivedTextToDiskKey) as? Bool ?? true
        self.saveReceivedFilesToDisk = defaults.object(forKey: Self.saveReceivedFilesToDiskKey) as? Bool ?? true
        self.savedItemsBaseDirectoryPath = defaults.string(forKey: Self.savedItemsBaseDirectoryPathKey)
            ?? ReceivedItemDiskStore.defaultBaseDirectory.path
        self.requireDeviceApproval = defaults.object(forKey: Self.requireDeviceApprovalKey) as? Bool ?? true
        self.applyAppPoliciesToIncomingItems = defaults.object(forKey: Self.applyAppPoliciesToIncomingItemsKey) as? Bool ?? true
        self.blockPasswordManagerClips = defaults.object(forKey: Self.blockPasswordManagerClipsKey) as? Bool ?? true
        self.temporarySyncUntil = defaults.object(forKey: Self.temporarySyncUntilKey) as? Date
        self.deviceTrustStore = DeviceTrustStore(defaults: defaults)
        self.pinnedFingerprints = Self.loadStringSet(forKey: Self.pinnedFingerprintsKey)
        self.favoriteFingerprints = Self.loadStringSet(forKey: Self.favoriteFingerprintsKey)
        self.excludedAppMap = Self.loadStringDictionary(forKey: Self.excludedAppsKey)
        self.frontmostApplicationName = frontmost.name ?? "Unknown App"
        self.effectiveColorScheme = nil
        self.appIconImage = AppIconProvider.loadAppIcon()
        self.lastObservedChangeCount = NSPasteboard.general.changeCount
        self.lastKnownPayload = ClipboardPayloadReader.readPayload(
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
        loadPersistedHistory()

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

        registerConnectivityObservers()
        updatePowerMonitoring()
        setupHotkeys()
    }

    deinit {
        MainActor.assumeIsolated {
            prepareForTermination()
        }
    }

    func prepareForTermination() {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true

        clipboardTask?.cancel()
        clipboardTask = nil
        connectivityHeartbeatTask?.cancel()
        connectivityHeartbeatTask = nil
        connectivityWatchdogTask?.cancel()
        connectivityWatchdogTask = nil
        lostPeerTasksByDeviceID.values.forEach { $0.cancel() }
        lostPeerTasksByDeviceID.removeAll()
        syncExpirationTask?.cancel()
        syncExpirationTask = nil
        thumbnailTasksByFingerprint.values.forEach { $0.cancel() }
        thumbnailTasksByFingerprint.removeAll()
        clearCopiedStateTask?.cancel()
        clearCopiedStateTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopPowerMonitoring()
        hotkeyManager.unregisterAll()
        historyPersistTask?.cancel()
        if clearHistoryOnQuit {
            deletePersistedHistory()
        } else {
            writeHistory(clipboardHistory)
        }
        stopServices()
        session = nil
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
        ClipboardHistoryStore.sorted(clipboardHistory).first
    }

    func imageThumbnail(for item: ClipboardHistoryItem) -> NSImage? {
        imageThumbnailByFingerprint[item.fingerprint]
    }

    var latestImageItem: ClipboardHistoryItem? {
        clipboardHistory.first(where: { $0.kind == .image })
    }

    var hasClearableHistory: Bool {
        ClipboardHistoryStore.hasClearableItems(clipboardHistory)
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

    var savedItemsDirectoryDisplayPath: String {
        (savedItemsBaseDirectoryPath as NSString).abbreviatingWithTildeInPath
    }

    func filteredHistory(searchText: String, filter: HistoryFilter) -> [ClipboardHistoryItem] {
        ClipboardHistoryStore.filtered(clipboardHistory, searchText: searchText, filter: filter)
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
        guard guardSensitivePayload(item.payload, action: .manualSend) else { return }
        sendPayload(item.payload, toDeviceIDs: [deviceID], historyItemID: item.id, sendOnly: true)
    }

    func sendCurrentClipboard(to deviceID: String) {
        let frontmost = MacSystemServices.frontmostApplicationInfo()
        frontmostApplicationName = frontmost.name ?? frontmostApplicationName

        guard let payload = ClipboardPayloadReader.readPayload(
            from: NSPasteboard.general,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: frontmost.bundleID,
            sourceAppName: frontmost.name
        ) else {
            statusText = "Nothing sendable is in the clipboard."
            return
        }

        guard !shouldSuppressSync(for: payload) else { return }
        guard guardSensitivePayload(payload, action: .manualSend) else { return }

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
        deletePersistedHistory()
        statusText = "Local history cleared."
    }

    func clearNonRetainedHistory() {
        let removedCount = ClipboardHistoryStore.clearNonRetainedItems(&clipboardHistory)

        guard removedCount > 0 else {
            statusText = "Only pinned and favorited clips remain."
            return
        }

        clipboardHistory.removeAll { !$0.isPinned && !$0.isFavorite }
        statusText = "Cleared \(removedCount) history item\(removedCount == 1 ? "" : "s")."
    }

    func deleteHistoryItem(_ item: ClipboardHistoryItem) {
        deleteHistoryItem(id: item.id)
    }

    func deleteHistoryItem(id: UUID) {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == id }) else { return }
        let removed = clipboardHistory.remove(at: index)
        pinnedFingerprints.remove(removed.fingerprint)
        favoriteFingerprints.remove(removed.fingerprint)
        saveStringSet(pinnedFingerprints, key: Self.pinnedFingerprintsKey)
        saveStringSet(favoriteFingerprints, key: Self.favoriteFingerprintsKey)
        scheduleHistoryPersist()
        statusText = "Clip deleted."
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
        guard trustState(for: deviceID) == .trusted else {
            statusText = "Trust this Mac before changing auto-sync."
            return
        }

        deviceTrustStore.setAutoSyncEnabled(enabled, for: deviceID)
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
            let url = try ClipboardPayloadWriter.temporaryFileURL(for: "AirCopy-Latest.png", data: imageData)
            NSWorkspace.shared.open(url)
            statusText = "Opened latest image."
        } catch {
            statusText = "Unable to open image: \(error.localizedDescription)"
        }
    }

    func trustPeer(_ deviceID: String) {
        deviceTrustStore.trust(deviceID)
        deviceTrustStore.setAutoSyncEnabled(autoSyncNewDevices, for: deviceID)
        updateTrustState(for: deviceID, to: .trusted)
        updatePeer(deviceID: deviceID) { $0.isAutoSyncEnabled = autoSyncNewDevices }
        inviteIfPossible(deviceID: deviceID)
        refreshPeerDevices()
        statusText = "Trusted \(peerStateByID[deviceID]?.displayName ?? "device")."
    }

    func blockPeer(_ deviceID: String) {
        deviceTrustStore.block(deviceID)
        updateTrustState(for: deviceID, to: .blocked)

        if let peer = peerIDByDeviceID[deviceID] {
            session.cancelConnectPeer(peer)
        }

        statusText = "Blocked \(peerStateByID[deviceID]?.displayName ?? "device")."
    }

    func addFrontmostApplicationToExclusions() {
        let frontmost = MacSystemServices.frontmostApplicationInfo()
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

    /// Brings sync online at launch: records the current clipboard, starts the
    /// clipboard monitor and connectivity services, and reports readiness.
    func start() {
        if let temporarySyncUntil, temporarySyncUntil <= Date() {
            self.temporarySyncUntil = nil
            syncEnabled = false
        }

        if let payload = lastKnownPayload,
           !clipboardHistory.contains(where: { $0.fingerprint == payload.fingerprint }),
           !shouldSuppressSync(for: payload) {
            _ = recordHistory(
                payload: payload,
                source: "Current clipboard on this Mac",
                senderName: localDeviceName,
                date: Date()
            )
        }

        if syncEnabled {
            startServices()
        }

        startClipboardMonitor()
        startConnectivityHeartbeat()
        startConnectivityWatchdog()
        scheduleSyncExpirationTask()

        statusText = syncEnabled
            ? (connectedPeerCount == 0 ? "Approve a nearby Mac or keep syncing locally." : "Ready.")
            : "Sync is off."
    }

    private func startServices() {
        guard !isPreparingForTermination else { return }
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
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session?.delegate = nil
        session?.disconnect()
        pendingConnectionAttemptAtByDeviceID.removeAll()

        for id in peerStateByID.keys {
            peerStateByID[id]?.isConnected = false
            peerStateByID[id]?.isDiscovered = false
        }

        guard !isPreparingForTermination else { return }
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

    private func startConnectivityHeartbeat() {
        connectivityHeartbeatTask?.cancel()
        let interval = connectivityHeartbeatInterval
        connectivityHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await MainActor.run {
                    self?.sendPresenceHeartbeatIfNeeded()
                }
            }
        }
    }

    private func startConnectivityWatchdog() {
        connectivityWatchdogTask?.cancel()
        let interval = connectivityWatchdogInterval
        connectivityWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await MainActor.run {
                    self?.performConnectivityWatchdogCheck()
                }
            }
        }
    }

    private func registerConnectivityObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceScreensDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    private func handleWorkspaceConnectivityRefresh(reason: String) {
        noteConnectivityEvent()

        if connectedPeerCount > 0 {
            restartDiscoveryServices()
            statusText = reason
            return
        }

        scheduleConnectivityRecovery(reason: reason, delay: .milliseconds(350), allowSessionRebuild: true)
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        handleWorkspaceConnectivityRefresh(reason: "Mac woke up. Refreshing nearby Macs...")
    }

    @objc private func workspaceScreensDidWake(_ notification: Notification) {
        handleWorkspaceConnectivityRefresh(reason: "Display woke up. Refreshing nearby Macs...")
    }

    private func noteConnectivityEvent(at date: Date = Date()) {
        lastConnectivityEventAt = date
    }

    private func cancelLostPeerGrace(for deviceID: String) {
        lostPeerTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
    }

    private func scheduleLostPeerGrace(for deviceID: String, peerName: String) {
        cancelLostPeerGrace(for: deviceID)
        let graceInterval = lostPeerGraceInterval

        lostPeerTasksByDeviceID[deviceID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(graceInterval))

            await MainActor.run {
                guard let self else { return }
                defer { self.lostPeerTasksByDeviceID[deviceID] = nil }

                guard !self.connectedDeviceIDs.contains(deviceID) else { return }
                guard self.peerStateByID[deviceID]?.isDiscovered == true else { return }

                self.updatePeer(deviceID: deviceID) { peer in
                    peer.isDiscovered = false
                }
                self.refreshPeerDevices()

                if self.trustState(for: deviceID) == .trusted {
                    self.scheduleConnectivityRecovery(
                        reason: "Lost sight of \(peerName). Refreshing nearby Macs...",
                        delay: .milliseconds(450),
                        allowSessionRebuild: true
                    )
                }
            }
        }
    }

    private func restartDiscoveryServices() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        startServices()
    }

    private func rebuildSessionAndRestartServices(reason: String) {
        guard !isPreparingForTermination else { return }

        let now = Date()
        if let lastConnectivityResetAt,
           now.timeIntervalSince(lastConnectivityResetAt) < minimumConnectivityResetSpacing {
            return
        }

        lastConnectivityResetAt = now

        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        pendingConnectionAttemptAtByDeviceID.removeAll()

        let oldSession = session
        oldSession?.delegate = nil
        oldSession?.disconnect()

        let newSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        newSession.delegate = self
        session = newSession

        for id in peerStateByID.keys {
            peerStateByID[id]?.isConnected = false
        }

        refreshPeerDevices()
        startServices()
        statusText = reason
    }

    private func scheduleConnectivityRecovery(
        reason: String,
        delay: Duration = .seconds(1),
        allowSessionRebuild: Bool
    ) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)

            await MainActor.run {
                self?.recoverConnectivityIfNeeded(reason: reason, allowSessionRebuild: allowSessionRebuild)
            }
        }
    }

    private func recoverConnectivityIfNeeded(reason: String, allowSessionRebuild: Bool) {
        guard syncEnabled else { return }

        let reconnectableTrustedPeers = peerDevices.filter {
            $0.trustState == .trusted && ($0.isDiscovered || peerIDByDeviceID[$0.id] != nil)
        }

        guard !reconnectableTrustedPeers.isEmpty else { return }

        if advertiser == nil || browser == nil {
            restartDiscoveryServices()
        }

        for peer in reconnectableTrustedPeers where !peer.isConnected && peer.isDiscovered {
            inviteIfPossible(deviceID: peer.id)
        }

        guard allowSessionRebuild, connectedPeerCount == 0 else {
            statusText = reason
            return
        }

        let stalledFor = Date().timeIntervalSince(lastConnectivityEventAt)
        guard stalledFor >= stalledConnectivityResetInterval else {
            statusText = reason
            return
        }

        rebuildSessionAndRestartServices(reason: reason)
    }

    private func performConnectivityWatchdogCheck() {
        guard syncEnabled else { return }

        let trustedPeersNeedingAttention = peerDevices.filter {
            $0.trustState == .trusted && !$0.isConnected && ($0.isDiscovered || peerIDByDeviceID[$0.id] != nil)
        }

        guard !trustedPeersNeedingAttention.isEmpty else { return }

        recoverConnectivityIfNeeded(
            reason: "Refreshing the nearby Mac connection...",
            allowSessionRebuild: true
        )
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
        _ = consumeClipboardChange()
    }

    @discardableResult
    private func consumeClipboardChange(
        localSource: String = "Copied on this Mac",
        localImagePausedStatus: String = "Saved image locally. Image sync is paused.",
        localSyncOffStatus: String = "Saved locally. Sync is off."
    ) -> Bool {
        let frontmost = MacSystemServices.frontmostApplicationInfo()
        frontmostApplicationName = frontmost.name ?? "Unknown App"

        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        guard changeCount != lastObservedChangeCount else { return false }
        lastObservedChangeCount = changeCount

        guard let rawPayload = ClipboardPayloadReader.readPayload(
            from: pasteboard,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: frontmost.bundleID,
            sourceAppName: frontmost.name
        ) else {
            lastKnownPayload = nil
            return false
        }

        if pendingRemotePayload == rawPayload {
            pendingRemotePayload = nil
            lastKnownPayload = rawPayload
            _ = recordHistory(
                payload: rawPayload,
                source: "Received from a trusted Mac",
                senderName: "Peer",
                date: Date(),
                deliveredRemotely: true
            )
            return true
        }

        let payload = rawPayload
        guard payload != lastKnownPayload else { return false }
        lastKnownPayload = payload

        guard !shouldSuppressSync(for: payload) else { return false }

        if payload != rawPayload {
            writePayloadToPasteboard(payload)
        }

        let item = recordHistory(
            payload: payload,
            source: localSource,
            senderName: localDeviceName,
            date: Date()
        )

        if payload.kind == .image && !imageSyncEnabled {
            statusText = localImagePausedStatus
            return true
        }

        guard syncEnabled else {
            statusText = localSyncOffStatus
            return true
        }

        guard guardSensitivePayload(payload, action: .automaticSync) else { return true }

        sendPayload(payload, toDeviceIDs: autoSyncPeers.map(\.id), historyItemID: item.id)
        return true
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
        noteConnectivityEvent(at: message.sentAt)

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
        peerIDByDeviceID[message.senderID] = peer

        if message.payload.kind == .image && !imageSyncEnabled {
            statusText = "Ignored image from \(message.senderName). Image sync is paused."
            sendReceipt(.skipped, for: message, to: peer)
            return
        }

        if shouldSuppressIncomingClipboard(message.payload, senderName: message.senderName) {
            sendReceipt(.skipped, for: message, to: peer)
            return
        }

        if let senderDeviceID = peerDisplayNameToDeviceID[peer.displayName] {
            updatePeer(deviceID: senderDeviceID) { peerState in
                peerState.lastSyncAt = Date()
                peerState.lastClipboardSummary = message.payload.title
            }
        }

        noteConnectivityEvent()

        applyIncomingClipboardMessage(message)
        sendReceipt(.clipboardUpdated, for: message, to: peer)
    }

    private func applyIncomingClipboardMessage(_ message: ClipboardMessage, statusPrefix: String = "Clipboard updated") {
        pendingRemotePayload = message.payload
        lastKnownPayload = message.payload
        writePayloadToPasteboard(message.payload)
        playSelectionSound()
        _ = recordHistory(
            payload: message.payload,
            source: "Received from \(message.senderName)",
            senderName: message.senderName,
            date: message.sentAt,
            deliveredRemotely: true
        )

        switch saveReceivedPayloadToDiskIfNeeded(message.payload, date: message.sentAt) {
        case .saved(let summary):
            statusText = "\(statusPrefix) from \(message.senderName). \(summary)"
        case .failed(let summary):
            statusText = "\(statusPrefix) from \(message.senderName). \(summary)"
        case .skipped:
            statusText = "\(statusPrefix) from \(message.senderName)."
        }
    }

    private func handleReceipt(_ receipt: ClipboardReceipt) {
        guard let historyItemID = outboundMessageHistoryMap[receipt.messageID] else { return }

        let state: DeliveryState

        switch receipt.kind {
        case .clipboardUpdated:
            state = .clipboardUpdated
        case .delivered:
            state = .delivered
        case .skipped:
            state = .skipped
        }

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
            peerState.lastReceiptText = state == .clipboardUpdated
                ? "Clipboard updated"
                : state.title
        }

        refreshPeerDevices()
        switch state {
        case .clipboardUpdated:
            statusText = "\(receipt.recipientName) updated its clipboard."
        case .delivered:
            statusText = "Delivered to \(receipt.recipientName)."
        case .skipped:
            statusText = "\(receipt.recipientName) skipped this clip."
        case .pending, .failed:
            statusText = state.title
        }
    }

    private func handlePresence(_ presence: PeerPresence, from peer: MCPeerID) {
        let receivedAt = Date()
        let resolvedID = upsertPeer(
            displayName: peer.displayName,
            deviceID: presence.senderID,
            discovered: true,
            connected: session.connectedPeers.contains(peer)
        )
        peerIDByDeviceID[resolvedID] = peer
        cancelLostPeerGrace(for: resolvedID)
        noteConnectivityEvent(at: receivedAt)

        updatePeer(deviceID: resolvedID) { peerState in
            peerState.lastSeenAt = receivedAt
            peerState.lastReceiptText = "Nearby"
        }

        refreshPeerDevices()
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

    private func sendReceipt(_ kind: ClipboardReceiptKind, for message: ClipboardMessage, toDeviceID senderDeviceID: String) {
        guard let peer = peerIDByDeviceID[senderDeviceID] else { return }
        sendReceipt(kind, for: message, to: peer)
    }

    private func sendPresenceHeartbeatIfNeeded() {
        let targets = trustedConnectedPeers.compactMap { peerState -> (String, String, MCPeerID)? in
            guard let peer = peerIDByDeviceID[peerState.id] else { return nil }
            return (peerState.id, peerState.displayName, peer)
        }

        guard !targets.isEmpty else { return }

        let presence = PeerPresence(senderID: deviceID, senderName: localDeviceName, sentAt: Date())
        noteConnectivityEvent(at: presence.sentAt)

        let data: Data
        do {
            data = try JSONEncoder().encode(AirCopyWireMessage.presence(presence))
        } catch {
            return
        }

        for (deviceID, displayName, peer) in targets {
            do {
                try session.send(data, toPeers: [peer], with: .unreliable)
                updatePeer(deviceID: deviceID) { peerState in
                    peerState.lastSeenAt = presence.sentAt
                }
            } catch {
                updatePeer(deviceID: deviceID) { peerState in
                    peerState.isConnected = false
                    peerState.lastReceiptState = .failed
                    peerState.lastReceiptText = "Connection dropped"
                }

                scheduleConnectivityRecovery(
                    reason: "Refreshing connection to \(displayName)...",
                    delay: .milliseconds(300),
                    allowSessionRebuild: true
                )
            }
        }

        refreshPeerDevices()
    }

    private func writePayloadToPasteboard(_ payload: ClipboardPayload) {
        lastObservedChangeCount = ClipboardPayloadWriter.writePayloadToGeneralPasteboard(payload)
    }

    private func recordHistory(
        payload: ClipboardPayload,
        source: String,
        senderName: String,
        date: Date,
        deliveredRemotely: Bool = false
    ) -> ClipboardHistoryItem {
        let item = ClipboardHistoryStore.record(
            payload: payload,
            source: source,
            senderName: senderName,
            date: date,
            deliveredRemotely: deliveredRemotely,
            history: &clipboardHistory,
            pinnedFingerprints: pinnedFingerprints,
            favoriteFingerprints: favoriteFingerprints,
            maxItems: maxHistoryItems
        )
        pruneThumbnailStateToCurrentHistory()
        scheduleThumbnailGenerationIfNeeded(for: item)
        return item
    }

    private func updateHistoryItem(id: UUID, source: String, senderName: String, date: Date) {
        guard ClipboardHistoryStore.updateItem(
            id: id,
            source: source,
            senderName: senderName,
            date: date,
            history: &clipboardHistory,
            maxItems: maxHistoryItems
        ) else { return }
        pruneThumbnailStateToCurrentHistory()
    }

    private func sortAndTrimHistory() {
        let retainedFingerprints = ClipboardHistoryStore.sortAndTrim(&clipboardHistory, maxItems: maxHistoryItems)
        imageThumbnailByFingerprint = imageThumbnailByFingerprint.filter { retainedFingerprints.contains($0.key) }
        thumbnailTasksByFingerprint = thumbnailTasksByFingerprint.filter { retainedFingerprints.contains($0.key) }
        scheduleHistoryPersist()
    }

    // MARK: - History persistence

    private static var historyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AirCopy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadPersistedHistory() {
        guard let data = try? Data(contentsOf: Self.historyFileURL),
              let items = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else { return }
        clipboardHistory = items
        pinnedFingerprints = Set(items.filter(\.isPinned).map(\.fingerprint))
        favoriteFingerprints = Set(items.filter(\.isFavorite).map(\.fingerprint))
        sortAndTrimHistory()
    }

    private func scheduleHistoryPersist() {
        historyPersistTask?.cancel()
        let snapshot = clipboardHistory
        historyPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.writeHistory(snapshot)
        }
    }

    private func writeHistory(_ items: [ClipboardHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.historyFileURL, options: .atomic)
    }

    private func deletePersistedHistory() {
        historyPersistTask?.cancel()
        try? FileManager.default.removeItem(at: Self.historyFileURL)
    }

    private func pruneThumbnailStateToCurrentHistory() {
        let retainedFingerprints = Set(clipboardHistory.map(\.fingerprint))
        imageThumbnailByFingerprint = imageThumbnailByFingerprint.filter { retainedFingerprints.contains($0.key) }
        thumbnailTasksByFingerprint = thumbnailTasksByFingerprint.filter { retainedFingerprints.contains($0.key) }
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

    private func updateEffectiveColorScheme() {
        switch appearancePreference {
        case .automatic:
            // Follow the macOS system appearance — `nil` lets SwiftUI inherit it
            // and update live when the user flips Light/Dark in System Settings.
            effectiveColorScheme = nil
        case .light:
            effectiveColorScheme = .light
        case .dark:
            effectiveColorScheme = .dark
        }
    }

    private func playSelectionSound() {
        guard soundEnabled else { return }
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func scheduleThumbnailGenerationIfNeeded(for item: ClipboardHistoryItem) {
        guard imageThumbnailByFingerprint[item.fingerprint] == nil else { return }
        guard thumbnailTasksByFingerprint[item.fingerprint] == nil else { return }

        let sourceData: Data?
        if let imageData = item.payload.imageData {
            sourceData = imageData
        } else if item.payload.isImageFileAttachment,
                  item.payload.attachments.count == 1,
                  let inlineData = item.payload.attachments.first?.inlineData {
            sourceData = inlineData
        } else {
            sourceData = nil
        }

        guard let sourceData else { return }
        let fingerprint = item.fingerprint

        thumbnailTasksByFingerprint[fingerprint] = Task.detached(priority: .utility) { [sourceData] in
            let thumbnail = ClipboardThumbnailFactory.thumbnailImage(from: sourceData, maxPixelSize: 160)

            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.thumbnailTasksByFingerprint[fingerprint] = nil }

                guard let thumbnail else { return }
                self.imageThumbnailByFingerprint[fingerprint] = thumbnail
            }
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
        guard shouldInitiateConnection(to: deviceID) else { return }
        guard deviceTrustStore.isExplicitlyTrusted(deviceID) else { return }
        guard let peer = peerIDByDeviceID[deviceID] else { return }
        guard !session.connectedPeers.contains(peer) else { return }
        guard !hasPendingConnection(to: deviceID) else { return }
        guard shouldAttemptInvite(to: deviceID) else { return }

        let context = PeerInvitationContext(deviceID: self.deviceID, deviceName: localDeviceName)
        let contextData = try? JSONEncoder().encode(context)
        lastInviteAttemptByDeviceID[deviceID] = Date()
        markConnectionPending(to: deviceID)
        browser?.invitePeer(peer, to: session, withContext: contextData, timeout: 10)
    }

    private func shouldInitiateConnection(to remoteDeviceID: String) -> Bool {
        guard remoteDeviceID != deviceID else { return false }
        return deviceID.localizedStandardCompare(remoteDeviceID) == .orderedAscending
    }

    private func shouldAttemptInvite(to deviceID: String) -> Bool {
        guard let lastAttemptAt = lastInviteAttemptByDeviceID[deviceID] else {
            return true
        }

        return Date().timeIntervalSince(lastAttemptAt) >= inviteRetryInterval
    }

    private func hasPendingConnection(to deviceID: String, at date: Date = Date()) -> Bool {
        guard let pendingAt = pendingConnectionAttemptAtByDeviceID[deviceID] else { return false }
        return date.timeIntervalSince(pendingAt) < pendingConnectionTimeout
    }

    private func markConnectionPending(to deviceID: String, at date: Date = Date()) {
        pendingConnectionAttemptAtByDeviceID[deviceID] = date
    }

    private func clearPendingConnection(to deviceID: String) {
        pendingConnectionAttemptAtByDeviceID.removeValue(forKey: deviceID)
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
        let autoSyncEligibleDeviceIDs = deviceTrustStore.enableAutoSyncForAllTrustedDevices(
            peerIDs: Set(peerStateByID.keys),
            requireDeviceApproval: requireDeviceApproval
        )

        for deviceID in autoSyncEligibleDeviceIDs {
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
                resolvedDeviceID(for: peer)
            }
        )
    }

    private func resolvedDeviceID(for peerID: MCPeerID) -> String {
        deviceIDByPeerID[peerID] ?? peerDisplayNameToDeviceID[peerID.displayName] ?? peerID.displayName
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
        deviceTrustStore.trustState(for: deviceID, requireDeviceApproval: requireDeviceApproval)
    }

    private func autoSyncEnabledState(for deviceID: String, trustState: PeerTrustState? = nil) -> Bool {
        let resolvedTrustState = trustState ?? self.trustState(for: deviceID)
        return deviceTrustStore.isAutoSyncEnabled(for: deviceID, trustState: resolvedTrustState)
    }

    private var savedItemsBaseDirectoryURL: URL {
        ReceivedItemDiskStore.baseDirectoryURL(for: savedItemsBaseDirectoryPath)
    }

    private func saveReceivedPayloadToDiskIfNeeded(_ payload: ClipboardPayload, date: Date) -> SaveReceivedPayloadResult {
        ReceivedItemDiskStore.save(
            payload: payload,
            date: date,
            settings: ReceivedItemDiskSettings(
                baseDirectoryPath: savedItemsBaseDirectoryPath,
                saveItems: saveReceivedItemsToDiskEnabled,
                saveImages: saveReceivedImagesToDisk,
                saveText: saveReceivedTextToDisk,
                saveFiles: saveReceivedFilesToDisk
            )
        )
    }

    private func shouldSuppressSync(for payload: ClipboardPayload) -> Bool {
        if let message = ClipboardPrivacyRules.outgoingSuppressionMessage(
            for: payload,
            blockPasswordManagerClips: blockPasswordManagerClips,
            excludedAppMap: excludedAppMap
        ) {
            statusText = message
            return true
        }

        if isImageOverLimit(payload) {
            statusText = "Image is larger than the sync limit. Skipped."
            return true
        }

        return false
    }

    /// True when the clip is an image bigger than the configured max image size.
    private func isImageOverLimit(_ payload: ClipboardPayload) -> Bool {
        guard maxImageBytes > 0 else { return false }
        guard payload.kind == .image, let bytes = payload.imageData?.count else { return false }
        return bytes > maxImageBytes
    }

    // MARK: - Power monitoring (Pause on battery)

    private func updatePowerMonitoring() {
        if pauseOnBattery {
            if powerRunLoopSource == nil {
                let context = Unmanaged.passUnretained(self).toOpaque()
                if let source = IOPSNotificationCreateRunLoopSource({ ctx in
                    guard let ctx else { return }
                    let coordinator = Unmanaged<AirCopyCoordinator>.fromOpaque(ctx).takeUnretainedValue()
                    Task { @MainActor in coordinator.recomputeBatteryPause() }
                }, context)?.takeRetainedValue() {
                    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
                    powerRunLoopSource = source
                }
            }
            recomputeBatteryPause()
        } else {
            stopPowerMonitoring()
            if isPausedForBattery {
                isPausedForBattery = false
                resumeFromBatteryPause()
            }
        }
    }

    private func stopPowerMonitoring() {
        if let source = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerRunLoopSource = nil
        }
    }

    private func isRunningOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey] as? String else { continue }
            if state == kIOPSBatteryPowerValue { return true }
        }
        return false
    }

    private func recomputeBatteryPause() {
        let shouldPause = pauseOnBattery && isRunningOnBattery()
        guard shouldPause != isPausedForBattery else { return }
        isPausedForBattery = shouldPause
        if shouldPause {
            statusText = "Syncing paused — running on battery."
            stopServices()
        } else {
            resumeFromBatteryPause()
        }
    }

    private func resumeFromBatteryPause() {
        statusText = "Syncing resumed."
        if syncEnabled { startServices() }
    }

    // MARK: - Global hotkeys

    private func setupHotkeys() {
        for (id, def) in HotkeyBinding.defaultBindings() {
            let binding = hotkeyManager.savedBinding(id: id, default: def)
            hotkeyBindings[id] = binding
            registerHotkey(id: id, binding: binding)
        }
    }

    private func registerHotkey(id: String, binding: HotkeyBinding) {
        hotkeyManager.register(id: id, binding: binding) { [weak self] in
            guard let self else { return }
            switch id {
            case "open": self.showMainWindow()
            case "copySync": self.sendCurrentClipboardToAllDevices()
            case "pasteLast": self.pasteLatestClip()
            default: break
            }
        }
    }

    func setHotkey(_ id: String, _ binding: HotkeyBinding) {
        hotkeyBindings[id] = binding
        hotkeyManager.saveBinding(id: id, binding)
        registerHotkey(id: id, binding: binding)
        statusText = "Shortcut updated."
    }

    func resetHotkeys() {
        for (id, def) in HotkeyBinding.defaultBindings() { setHotkey(id, def) }
    }

    // MARK: - Hotkey actions

    func sendCurrentClipboardToAllDevices() {
        let targets = autoSyncPeers.map(\.id)
        guard !targets.isEmpty else { statusText = "No synced Macs to send to."; return }
        for id in targets { sendCurrentClipboard(to: id) }
    }

    func pasteLatestClip() {
        guard let item = latestClipboardItem else { statusText = "No clips to paste."; return }
        writePayloadToPasteboard(item.payload)
        lastKnownPayload = item.payload
        _ = MacSystemServices.pasteIntoFrontmostApplication()
    }

    // MARK: - Updates

    private static let updateManifestURL = URL(string: "https://aircopy-karnagebitcoin.netlify.app/version.json")!

    func checkForUpdates() {
        updateCheckStatus = "Checking…"
        Task { await performUpdateCheck() }
    }

    private func performUpdateCheck() async {
        struct Manifest: Decodable { let version: String; let build: Int; let url: String? }
        do {
            var request = URLRequest(url: Self.updateManifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
            if manifest.build > currentBuild {
                updateCheckStatus = "Update available: \(manifest.version)"
                if let urlString = manifest.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                updateCheckStatus = "You're on the latest version."
            }
        } catch {
            updateCheckStatus = "Couldn't reach the update server."
        }
    }

    // MARK: - Reset

    func resetAllSettings() {
        syncEnabled = true
        imageSyncEnabled = true
        requireDeviceApproval = true
        blockPasswordManagerClips = true
        soundEnabled = false
        historyLimit = 50
        maxImageBytes = 25 * 1024 * 1024
        clearHistoryOnQuit = false
        pauseOnBattery = false
        autoSyncNewDevices = true
        statusText = "Settings reset to defaults."
    }

    private func shouldSuppressIncomingClipboard(_ payload: ClipboardPayload, senderName: String) -> Bool {
        if isImageOverLimit(payload) {
            statusText = "Incoming image exceeds the size limit. Skipped."
            return true
        }

        guard let message = ClipboardPrivacyRules.incomingSuppressionMessage(
            for: payload,
            senderName: senderName,
            blockPasswordManagerClips: blockPasswordManagerClips,
            applyAppPoliciesToIncomingItems: applyAppPoliciesToIncomingItems,
            excludedAppMap: excludedAppMap
        ) else { return false }

        statusText = message
        return true
    }

    private func guardSensitivePayload(_ payload: ClipboardPayload, action: SensitiveContentAction) -> Bool {
        switch ClipboardPrivacyRules.sensitiveContentResult(
            for: payload,
            action: action,
            existingApproval: sensitiveContentApproval
        ) {
        case .allowed(let clearApproval):
            if clearApproval {
                sensitiveContentApproval = nil
            }
            return true
        case .blocked(let message):
            statusText = message
            return false
        case .needsConfirmation(let message, let approval):
            sensitiveContentApproval = approval
            statusText = message
            return false
        }
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

            if contextValue?.deviceID == self.deviceID {
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
            self.deviceIDByPeerID[peerBox.peerID] = resolvedID
            let trustState = self.trustState(for: resolvedID)

            guard trustState == .trusted else {
                self.statusText = trustState == .pending
                    ? "Approval required for \(peerName)."
                    : "Blocked invitation from \(peerName)."
                handlerBox.handler(false, nil)
                return
            }

            guard !self.shouldInitiateConnection(to: resolvedID) else {
                self.statusText = "Found \(peerName). Connecting..."
                handlerBox.handler(false, nil)
                self.inviteIfPossible(deviceID: resolvedID)
                return
            }

            guard !self.connectedDeviceIDs.contains(resolvedID),
                  !self.hasPendingConnection(to: resolvedID) else {
                handlerBox.handler(false, nil)
                return
            }

            self.statusText = "Connecting to \(peerName)..."
            self.markConnectionPending(to: resolvedID)
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
            if let discoveredDeviceID {
                guard discoveredDeviceID != self.deviceID else { return }
            } else {
                guard peerName != self.peerID.displayName else { return }
            }
            self.noteConnectivityEvent()

            let resolvedID = self.upsertPeer(
                displayName: peerName,
                deviceID: discoveredDeviceID,
                discovered: true,
                connected: false
            )
            self.peerIDByDeviceID[resolvedID] = peerBox.peerID
            self.deviceIDByPeerID[peerBox.peerID] = resolvedID
            self.cancelLostPeerGrace(for: resolvedID)

            guard self.trustState(for: resolvedID) == .trusted else {
                self.statusText = "Found \(peerName). Approval needed before connecting."
                return
            }

            if self.shouldInitiateConnection(to: resolvedID) {
                self.statusText = "Found \(peerName). Connecting..."
                self.inviteIfPossible(deviceID: resolvedID)
            } else {
                self.statusText = "Found \(peerName). Waiting for their connection..."
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peerBox = PeerIDBox(peerID)
        let peerName = peerID.displayName

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.noteConnectivityEvent()

            let resolvedID = self.resolvedDeviceID(for: peerBox.peerID)
            guard !self.connectedDeviceIDs.contains(resolvedID) else {
                return
            }
            self.scheduleLostPeerGrace(for: resolvedID, peerName: peerName)
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
        let peerBox = PeerIDBox(peerID)
        let peerName = peerID.displayName

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.noteConnectivityEvent()

            let resolvedID = self.resolvedDeviceID(for: peerBox.peerID)
            let trustState = self.trustState(for: resolvedID)
            self.deviceIDByPeerID[peerBox.peerID] = resolvedID

            _ = self.upsertPeer(
                displayName: peerName,
                deviceID: resolvedID == peerName ? self.peerDisplayNameToDeviceID[peerName] : resolvedID,
                discovered: state != .notConnected,
                connected: state == .connected
            )

            switch state {
            case .connected:
                self.clearPendingConnection(to: resolvedID)
                self.cancelLostPeerGrace(for: resolvedID)
                self.lastInviteAttemptByDeviceID[resolvedID] = nil
                self.statusText = "Connected to \(peerName)."

                if trustState == .trusted,
                   self.isAutoSyncEnabled(for: resolvedID),
                   let payload = self.lastKnownPayload,
                   self.syncEnabled {
                    guard self.guardSensitivePayload(payload, action: .automaticSync) else { return }
                    self.sendPayload(payload, toDeviceIDs: [resolvedID], historyItemID: self.latestClipboardItem?.id)
                }
            case .connecting:
                self.markConnectionPending(to: resolvedID)
                self.cancelLostPeerGrace(for: resolvedID)
                self.statusText = "Connecting to \(peerName)..."
            case .notConnected:
                self.clearPendingConnection(to: resolvedID)
                self.updatePeer(deviceID: resolvedID) { peer in
                    peer.isConnected = false
                }
                self.refreshPeerDevices()

                if trustState == .trusted {
                    self.statusText = "Reconnecting to \(peerName)..."
                    if self.peerStateByID[resolvedID]?.isDiscovered == true {
                        self.inviteIfPossible(deviceID: resolvedID)
                    }
                    self.scheduleConnectivityRecovery(
                        reason: "Reconnecting to \(peerName)...",
                        delay: .milliseconds(800),
                        allowSessionRebuild: true
                    )
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
                self.noteConnectivityEvent()

                switch wireMessage.kind {
                case .clipboard:
                    if let message = wireMessage.clipboard {
                        self.applyRemoteClipboard(message, fromPeer: peerBox.peerID)
                    }
                case .receipt:
                    if let receipt = wireMessage.receipt {
                        self.handleReceipt(receipt)
                    }
                case .presence:
                    if let presence = wireMessage.presence {
                        self.handlePresence(presence, from: peerBox.peerID)
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
