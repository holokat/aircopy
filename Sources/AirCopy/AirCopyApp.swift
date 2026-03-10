import SwiftUI

@main
struct AirCopyApp: App {
    @StateObject private var coordinator = AirCopyCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .preferredColorScheme(coordinator.effectiveColorScheme)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("AirCopy", systemImage: coordinator.menuBarSymbolName) {
            MenuBarContentView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}
