import AppKit
import ServiceManagement
import SwiftUI

// App-shell preferences (login item, menu-bar / Dock presence). Everything
// else in Settings is owned by AirCopyCoordinator with real backend effects.
@MainActor
final class AppSettingsStore: ObservableObject {
    @AppStorage("ac.settings.launchAtLogin") var launchAtLogin = false { didSet { applyLaunchAtLogin() } }
    @AppStorage("ac.settings.showInMenuBar") var showInMenuBar = true { didSet { onMenuBarChange?(showInMenuBar) } }
    @AppStorage("ac.settings.showInDock") var showInDock = true { didSet { applyDockVisibility() } }

    /// Hook so the status-item controller can react to menu-bar visibility.
    var onMenuBarChange: ((Bool) -> Void)?

    func applyOnLaunch() {
        applyLaunchAtLogin()
        applyDockVisibility()
    }

    func resetToDefaults() {
        launchAtLogin = false
        showInMenuBar = true
        showInDock = true
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
