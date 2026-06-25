import AppKit
import SwiftUI

/// Hides the window's native traffic-light buttons. SwiftUI's hidden-titlebar
/// window keeps re-laying the buttons to the top on every layout pass (so
/// `setFrameOrigin` can't be made to stick), but `isHidden` persists. We hide
/// the native buttons and draw our own centered dots in the titlebar instead.
struct TitlebarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfiguratorView)?.apply()
    }

    final class ConfiguratorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(apply), name: name, object: window)
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        @objc func apply() {
            let window = self.window ?? NSApplication.shared.windows.first {
                !$0.isSheet && $0.standardWindowButton(.closeButton) != nil
            }
            guard let window else { return }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

/// Custom macOS-style traffic lights drawn in the titlebar so they sit exactly
/// on the design's centered row. Wired to the key window's standard actions.
struct MacTrafficLights: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(hex: 0xFF5F57), symbol: "xmark") { keyWindow?.performClose(nil) }
            light(Color(hex: 0xFEBC2E), symbol: "minus") { keyWindow?.miniaturize(nil) }
            light(Color(hex: 0x28C840), symbol: "arrow.up.left.and.arrow.down.right") { keyWindow?.zoom(nil) }
        }
        .onHover { hovering = $0 }
    }

    private var keyWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && !$0.isSheet }
    }

    private func light(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                if hovering {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
