import AppKit
import SwiftUI

@main
struct AirCopyApp: App {
    @StateObject private var coordinator = AirCopyCoordinator()
    @StateObject private var statusItemController = AppKitStatusItemController()
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var toastCenter = ACToastCenter()
    @StateObject private var updater = SparkleUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(settingsStore)
                .environmentObject(toastCenter)
                .environmentObject(updater)
                .preferredColorScheme(coordinator.effectiveColorScheme)
                .frame(minWidth: 1100, idealWidth: 1240, maxWidth: .infinity, minHeight: 760, idealHeight: 858, maxHeight: .infinity)
                .background(
                    StatusItemInstallerView()
                        .environmentObject(coordinator)
                        .environmentObject(statusItemController)
                )
                .task {
                    settingsStore.onMenuBarChange = { [weak statusItemController] visible in
                        statusItemController?.setStatusItemVisible(visible)
                    }
                    settingsStore.applyOnLaunch()
                    statusItemController.setStatusItemVisible(settingsStore.showInMenuBar)
                    coordinator.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    statusItemController.prepareForTermination()
                    coordinator.prepareForTermination()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 1240, height: 858)
    }
}

private struct StatusItemInstallerView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @EnvironmentObject private var statusItemController: AppKitStatusItemController

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                statusItemController.install(coordinator: coordinator)
            }
    }
}
