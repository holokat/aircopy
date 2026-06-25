import Foundation

enum AppSourcePrivacyPolicy {
    static let protectedPasswordManagerApplications: [ProtectedAppRule] = [
        ProtectedAppRule(
            appName: "1Password",
            matchSummary: "com.1password.1password, com.agilebits.onepassword7, plus 1Password name matches"
        ),
        ProtectedAppRule(
            appName: "Bitwarden",
            matchSummary: "com.bitwarden.desktop, plus Bitwarden name matches"
        ),
        ProtectedAppRule(appName: "LastPass", matchSummary: "com.lastpass.LastPass"),
        ProtectedAppRule(appName: "RoboForm", matchSummary: "com.roboform.RoboForm"),
        ProtectedAppRule(appName: "Dashlane", matchSummary: "com.dashlane.dashlanephonefinal"),
        ProtectedAppRule(appName: "KeePassXC", matchSummary: "org.keepassxc.keepassxc")
    ]

    private static let protectedPasswordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.lastpass",
        "com.roboform.roboform",
        "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc"
    ]

    static func protectedSourceName(for payload: ClipboardPayload) -> String? {
        guard let bundleID = payload.sourceAppBundleID else { return nil }

        let lowercasedBundleID = bundleID.lowercased()
        let lowercasedSourceName = payload.sourceAppName?.lowercased() ?? ""

        if protectedPasswordManagerBundleIDs.contains(lowercasedBundleID)
            || lowercasedBundleID.contains("1password")
            || lowercasedBundleID.contains("bitwarden")
            || lowercasedSourceName.contains("1password")
            || lowercasedSourceName.contains("bitwarden") {
            return payload.sourceAppName ?? bundleID
        }

        return nil
    }
}
