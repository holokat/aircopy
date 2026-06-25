import Foundation

enum SensitivePayloadGuardResult {
    case allowed(clearApproval: Bool)
    case blocked(String)
    case needsConfirmation(String, SensitiveContentApproval)
}

enum ClipboardPrivacyRules {
    static func outgoingSuppressionMessage(
        for payload: ClipboardPayload,
        blockPasswordManagerClips: Bool,
        excludedAppMap: [String: String]
    ) -> String? {
        if blockPasswordManagerClips,
           let protectedSourceName = AppSourcePrivacyPolicy.protectedSourceName(for: payload) {
            return "Skipped clipboard from \(protectedSourceName)."
        }

        guard let bundleID = payload.sourceAppBundleID,
              let name = excludedAppMap[bundleID] else {
            return nil
        }

        return "Skipped clipboard from excluded app \(name)."
    }

    static func incomingSuppressionMessage(
        for payload: ClipboardPayload,
        senderName: String,
        blockPasswordManagerClips: Bool,
        applyAppPoliciesToIncomingItems: Bool,
        excludedAppMap: [String: String]
    ) -> String? {
        if blockPasswordManagerClips,
           let protectedSourceName = AppSourcePrivacyPolicy.protectedSourceName(for: payload) {
            return "Skipped \(senderName)'s clip from \(protectedSourceName)."
        }

        guard applyAppPoliciesToIncomingItems,
              let bundleID = payload.sourceAppBundleID,
              let name = excludedAppMap[bundleID] else {
            return nil
        }

        return "Skipped \(senderName)'s clip from excluded app \(name)."
    }

    static func sensitiveContentResult(
        for payload: ClipboardPayload,
        action: SensitiveContentAction,
        existingApproval: SensitiveContentApproval?,
        now: Date = Date()
    ) -> SensitivePayloadGuardResult {
        switch SensitiveContentPolicy.decision(for: payload) {
        case .allowed:
            return .allowed(clearApproval: false)
        case .blocked(let reason):
            return .blocked("\(reason) AirCopy kept it out of team sync.")
        case .confirm(let reason):
            if action == .automaticSync {
                return .blocked("\(reason) AirCopy kept it local.")
            }

            if let existingApproval,
               existingApproval.fingerprint == payload.fingerprint,
               existingApproval.expiresAt > now {
                return .allowed(clearApproval: true)
            }

            let approval = SensitiveContentApproval(
                fingerprint: payload.fingerprint,
                expiresAt: now.addingTimeInterval(30)
            )
            return .needsConfirmation("\(reason) \(confirmationInstruction(for: action))", approval)
        }
    }

    private static func confirmationInstruction(for action: SensitiveContentAction) -> String {
        switch action {
        case .automaticSync:
            return "AirCopy kept it local."
        case .manualSend:
            return "Use the same send action again within 30 seconds to send once."
        case .acceptIncoming:
            return "Press Accept again within 30 seconds to copy once."
        }
    }
}
