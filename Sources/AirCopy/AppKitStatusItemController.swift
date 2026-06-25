import AppKit
import Combine
import SwiftUI

@MainActor
final class AppKitStatusItemController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private weak var coordinator: AirCopyCoordinator?
    private weak var subscriptionManager: SubscriptionManager?
    private var cancellables: Set<AnyCancellable> = []
    private var isPreparingForTermination = false
    private var wantsVisible = true

    func install(coordinator: AirCopyCoordinator, subscriptionManager: SubscriptionManager) {
        guard !isPreparingForTermination else { return }

        self.coordinator = coordinator
        self.subscriptionManager = subscriptionManager
        coordinator.setSubscriptionAccess(subscriptionManager.hasActiveSubscription)

        createStatusItemIfNeeded()
        observeStateChanges()
        updateStatusButton()
    }

    /// Show or hide the menu-bar item (driven by the "Show in menu bar" setting).
    func setStatusItemVisible(_ visible: Bool) {
        wantsVisible = visible
        guard !isPreparingForTermination else { return }
        if visible {
            createStatusItemIfNeeded()
            updateStatusButton()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func prepareForTermination() {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true

        cancellables.removeAll()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }

        coordinator = nil
        subscriptionManager = nil
    }

    deinit {
        MainActor.assumeIsolated {
            prepareForTermination()
        }
    }

    private func createStatusItemIfNeeded() {
        guard wantsVisible, statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func observeStateChanges() {
        cancellables.removeAll()

        coordinator?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStatusButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let coordinator, let button = statusItem?.button else { return }
        button.image = menuIcon(coordinator.menuBarSymbolName, accessibilityDescription: "AirCopy")
        button.imagePosition = .imageLeft
        button.title = ""
        button.toolTip = "AirCopy"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            coordinator?.showMainWindow()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open AirCopy", action: #selector(openMain), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AirCopy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action == #selector(openMain) || item.action == #selector(openSettings) {
            item.target = self
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMain() { coordinator?.showMainWindow() }

    @objc private func openSettings() {
        coordinator?.showMainWindow()
        coordinator?.showSettings()
    }

    private func menuIcon(_ systemName: String, accessibilityDescription: String? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }
}
