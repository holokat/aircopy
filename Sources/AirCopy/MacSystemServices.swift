import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum MacSystemServices {
    enum PasteInvocationResult {
        case sent
        case accessibilityPermissionMissing
        case eventCreationFailed
    }

    static func frontmostApplicationInfo() -> (bundleID: String?, name: String?) {
        let application = NSWorkspace.shared.frontmostApplication
        return (application?.bundleIdentifier, application?.localizedName)
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }

    static func openAccessibilityPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func revealCurrentAppInFinder(fallbackURL: URL) {
        let resolvedURL = permissionTargetAppURL(fallbackURL: fallbackURL)
        _ = NSWorkspace.shared.selectFile(resolvedURL.path, inFileViewerRootedAtPath: "")
    }

    static func permissionTargetAppURL(fallbackURL: URL) -> URL {
        let targetURL = canonicalInstalledAppURL()
        return FileManager.default.fileExists(atPath: targetURL.path) ? targetURL : fallbackURL
    }

    static func pasteIntoFrontmostApplication() -> PasteInvocationResult {
        guard isAccessibilityTrusted() else {
            return .accessibilityPermissionMissing
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return .eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .sent
    }

    private static func canonicalInstalledAppURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("AirCopy.app", isDirectory: true)
    }
}
