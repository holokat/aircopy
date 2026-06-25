import AppKit
import ServiceManagement
import SwiftUI

// Persisted preferences for the redesigned Settings sheet that are NOT already
// owned by the coordinator. Coordinator-backed prefs (image sync, password
// blocking, device approval, history limit, sound) are bound directly to the
// coordinator from the settings UI; this store covers the rest.
@MainActor
final class AppSettingsStore: ObservableObject {
    enum NewDeviceMode: String { case sync, ask }
    enum SyncOver: String { case wifi, both }
    enum MaxImage: String { case five = "5", twentyFive = "25", any = "inf" }

    @AppStorage("ac.settings.launchAtLogin") var launchAtLogin = false { didSet { applyLaunchAtLogin() } }
    @AppStorage("ac.settings.showInMenuBar") var showInMenuBar = true { didSet { onMenuBarChange?(showInMenuBar) } }
    @AppStorage("ac.settings.showInDock") var showInDock = true { didSet { applyDockVisibility() } }

    @AppStorage("ac.settings.newDeviceMode") private var newDeviceModeRaw = NewDeviceMode.sync.rawValue
    @AppStorage("ac.settings.syncOver") private var syncOverRaw = SyncOver.wifi.rawValue
    @AppStorage("ac.settings.pauseOnBattery") var pauseOnBattery = false

    @AppStorage("ac.settings.maxImage") private var maxImageRaw = MaxImage.twentyFive.rawValue
    @AppStorage("ac.settings.clearOnQuit") var clearOnQuit = false

    @AppStorage("ac.settings.localOnly") var localNetworkOnly = true
    @AppStorage("ac.settings.encrypt") var encryptTransfers = true

    /// Hook so the status-item controller can react to menu-bar visibility.
    var onMenuBarChange: ((Bool) -> Void)?

    var newDeviceMode: NewDeviceMode {
        get { NewDeviceMode(rawValue: newDeviceModeRaw) ?? .sync }
        set { newDeviceModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var syncOver: SyncOver {
        get { SyncOver(rawValue: syncOverRaw) ?? .wifi }
        set { syncOverRaw = newValue.rawValue; objectWillChange.send() }
    }

    var maxImage: MaxImage {
        get { MaxImage(rawValue: maxImageRaw) ?? .twentyFive }
        set { maxImageRaw = newValue.rawValue; objectWillChange.send() }
    }

    func applyOnLaunch() {
        applyLaunchAtLogin()
        applyDockVisibility()
    }

    func resetToDefaults() {
        launchAtLogin = false
        showInMenuBar = true
        showInDock = true
        newDeviceMode = .sync
        syncOver = .wifi
        pauseOnBattery = false
        maxImage = .twentyFive
        clearOnQuit = false
        localNetworkOnly = true
        encryptTransfers = true
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Best-effort; login-item registration can fail in unsigned dev builds.
        }
    }

    private func applyDockVisibility() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
