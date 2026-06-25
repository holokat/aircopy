import AppKit
import SwiftUI

@main
struct AirCopyApp: App {
    @StateObject private var coordinator = AirCopyCoordinator()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var statusItemController = AppKitStatusItemController()
    @StateObject private var settingsStore = AppSettingsStore()
    @StateObject private var toastCenter = ACToastCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(subscriptionManager)
                .environmentObject(settingsStore)
                .environmentObject(toastCenter)
                .preferredColorScheme(.light)
                .frame(minWidth: 1040, minHeight: 720)
                .background(
                    StatusItemInstallerView()
                        .environmentObject(coordinator)
                        .environmentObject(subscriptionManager)
                        .environmentObject(statusItemController)
                )
                .task {
                    settingsStore.onMenuBarChange = { [weak statusItemController] visible in
                        statusItemController?.setStatusItemVisible(visible)
                    }
                    settingsStore.applyOnLaunch()
                    statusItemController.setStatusItemVisible(settingsStore.showInMenuBar)
                    await subscriptionManager.start()
                }
                .onChange(of: subscriptionManager.hasActiveSubscription, initial: true) { _, hasActiveSubscription in
                    coordinator.setSubscriptionAccess(hasActiveSubscription)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    statusItemController.prepareForTermination()
                    coordinator.prepareForTermination()
                    subscriptionManager.prepareForTermination()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

private struct StatusItemInstallerView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var statusItemController: AppKitStatusItemController

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                statusItemController.install(
                    coordinator: coordinator,
                    subscriptionManager: subscriptionManager
                )
            }
    }
}
