import Foundation

enum SensitiveContentAction {
    case automaticSync
    case manualSend
    case acceptIncoming
}

enum SensitiveContentDecision {
    case allowed
    case confirm(String)
    case blocked(String)
}

struct SensitiveContentApproval {
    let fingerprint: String
    let expiresAt: Date
}

enum SensitiveContentPolicy {
    static func decision(for payload: ClipboardPayload) -> SensitiveContentDecision {
        let text = sensitiveContentText(for: payload)
        guard !text.isEmpty else { return .allowed }

        if containsPrivateKey(text) {
            return .blocked("Private key material detected.")
        }

        if containsLikelySecret(text) {
            return .confirm("Possible token, API key, or credential detected.")
        }

        return .allowed
    }

    private static func sensitiveContentText(for payload: ClipboardPayload) -> String {
        switch payload.kind {
        case .text, .code, .link, .browserTab:
            return [payload.text, payload.urlString, payload.linkTitle]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .file, .folder:
            return payload.attachments.map { "\($0.name)\n\($0.originalPath)" }.joined(separator: "\n")
        case .image:
            return ""
        }
    }

    private static func containsPrivateKey(_ text: String) -> Bool {
        let uppercased = text.uppercased()
        return uppercased.contains("-----BEGIN OPENSSH PRIVATE KEY-----")
            || uppercased.contains("-----BEGIN RSA PRIVATE KEY-----")
            || uppercased.contains("-----BEGIN EC PRIVATE KEY-----")
            || uppercased.contains("-----BEGIN DSA PRIVATE KEY-----")
            || uppercased.contains("-----BEGIN PRIVATE KEY-----")
    }

    private static func containsLikelySecret(_ text: String) -> Bool {
        let patterns = [
            #"(?i)\b(sk_live|sk_test|rk_live|rk_test)_[A-Za-z0-9]{16,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#,
            #"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"#,
            #"\bAKIA[0-9A-Z]{16}\b"#,
            #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|secret)\s*[:=]\s*['"]?[A-Za-z0-9_\-./+=]{16,}"#
        ]

        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
