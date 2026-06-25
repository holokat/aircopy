import Foundation
import Testing

struct PackagingPolicyTests {
    @Test
    func packageScriptPrefersStableDeveloperSigningWhenAvailable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: repositoryRoot.appending(path: "scripts/package-app.sh"),
            encoding: .utf8
        )

        #expect(script.contains("AIRCOPY_CODE_SIGN_IDENTITY"))
        #expect(script.contains("security find-identity -p codesigning -v"))
        #expect(script.contains("Apple Development"))
        #expect(script.contains("--sign \"$SIGN_IDENTITY\""))
        #expect(script.contains("Falling back to ad-hoc signature"))
        #expect(script.contains("AIRCOPY_KEEP_STAGING_APP"))
        #expect(script.contains("rm -rf \"$APP_DIR\""))
    }
}
