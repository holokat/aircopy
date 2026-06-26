import Combine
import Sparkle
import SwiftUI

/// Thin SwiftUI-friendly wrapper around Sparkle's standard updater. Sparkle owns
/// the whole update experience (background checks, the download/install window
/// with a progress bar, signature verification, and relaunch); we just expose a
/// "Check for Updates" action and whether it's currently available.
@MainActor
final class SparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    init() {
        // startingUpdater: true kicks off Sparkle immediately (scheduled checks
        // use SUEnableAutomaticChecks / SUFeedURL / SUPublicEDKey from Info.plist).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Opens Sparkle's update flow (its own window with progress + relaunch).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
