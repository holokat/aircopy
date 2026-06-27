import Combine
import Sparkle
import SwiftUI

/// Thin SwiftUI-friendly wrapper around Sparkle's standard updater. Sparkle owns
/// the whole update experience (background checks, the download/install window
/// with a progress bar, signature verification, and relaunch); we just expose a
/// "Check for Updates" action and whether it's currently available.
@MainActor
final class SparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheckForUpdates = false

    /// Whether Sparkle checks for new versions automatically in the background.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        // Sparkle requires a real, code-signed .app bundle (its embedded
        // framework + XPC services). When running the unbundled debug binary
        // from `.build/debug`, the updater can't start and Sparkle would throw a
        // confusing "updater failed to start" alert — so only start it when we're
        // actually a bundled app.
        if Bundle.main.bundleURL.pathExtension == "app" {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.controller = controller
            self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .assign(to: &$canCheckForUpdates)
        } else {
            self.controller = nil
            self.automaticallyChecksForUpdates = false
        }
    }

    /// Opens Sparkle's update flow (its own window with progress + relaunch).
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
