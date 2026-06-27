import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that can take keyboard focus without activating the app as
/// a normal window would (Spotlight-style).
final class SpotlightPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the Spotlight overlay panel and drives show/hide + keyboard navigation.
@MainActor
final class ACSpotlightController: NSObject, ObservableObject, NSWindowDelegate {
    private let model = SpotlightModel()
    private var panel: SpotlightPanelWindow?
    private var keyMonitor: Any?
    private weak var coordinator: AirCopyCoordinator?
    private var isShown = false
    private var ignoreResignUntil: Date = .distantPast

    func install(coordinator: AirCopyCoordinator) {
        self.coordinator = coordinator
        model.coordinator = coordinator
        model.onClose = { [weak self] in self?.coordinator?.dismissSpotlight() }
    }

    /// Called by the app when `coordinator.spotlightPresented` changes.
    func setVisible(_ visible: Bool) {
        if visible { show() } else { hide() }
    }

    // MARK: Build

    private func ensurePanel() {
        guard panel == nil, let coordinator else { return }

        let rect = NSRect(x: 0, y: 0, width: 720, height: 496)
        let panel = SpotlightPanelWindow(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        // Vibrant dark backdrop (blurred wallpaper shows through), rounded.
        let effect = NSVisualEffectView(frame: rect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: ACSpotlightView(model: model).environmentObject(coordinator))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        self.panel = panel
    }

    // MARK: Show / hide

    private func show() {
        guard !isShown else { return }
        ensurePanel()
        guard let panel else { return }
        isShown = true
        ignoreResignUntil = Date().addingTimeInterval(0.5)
        model.reset()
        positionPanel(panel)
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func positionPanel(_ panel: NSWindow) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.minX + (frame.width - size.width) / 2
        let y = frame.minY + frame.height - size.height - frame.height * 0.16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns nil to consume the event, or the event to let it through (typing).
    private func handle(_ event: NSEvent) -> NSEvent? {
        // ⌘1…⌘9 quick-copy.
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...9).contains(digit) {
            model.quickCopy(digit)
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            coordinator?.dismissSpotlight()
            return nil
        case kVK_UpArrow:
            model.moveUp()
            return nil
        case kVK_DownArrow:
            model.moveDown()
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.copySelected()
            return nil
        default:
            return event // let the search field type
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away / switching apps dismisses the overlay — but ignore the
        // transient resign that happens during the activate/makeKey sequence.
        guard isShown, Date() >= ignoreResignUntil else { return }
        coordinator?.dismissSpotlight()
    }

    deinit {
        MainActor.assumeIsolated {
            removeKeyMonitor()
            panel?.orderOut(nil)
        }
    }
}
