import AppKit
@preconcurrency import CoreGraphics
import Foundation

enum NativeScreenshotCaptureMode {
    case currentDisplay
    case selection
}

enum NativeScreenshotCaptureError: LocalizedError {
    case screenRecordingPermissionDenied
    case noScreenAvailable
    case userCancelled
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Allow Screen Recording so AirCopy can capture screenshots directly."
        case .noScreenAvailable:
            return "No screen was available for screenshot capture."
        case .userCancelled:
            return "Screenshot capture was cancelled."
        case .captureFailed:
            return "AirCopy could not capture the screenshot."
        }
    }
}

@MainActor
final class NativeScreenshotCaptureController: NSObject {
    typealias Completion = (Result<Data, NativeScreenshotCaptureError>) -> Void

    private var overlayWindows: [ScreenshotOverlayWindow] = []
    private var keyMonitor: Any?
    private var completion: Completion?
    private var isCapturing = false

    static func preflightPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func capture(
        _ mode: NativeScreenshotCaptureMode,
        promptForPermission: Bool = true,
        completion: @escaping Completion
    ) {
        guard !isCapturing else { return }

        let permissionGranted = promptForPermission ? Self.requestPermission() : Self.preflightPermission()
        guard permissionGranted else {
            completion(.failure(.screenRecordingPermissionDenied))
            return
        }

        self.completion = completion
        isCapturing = true

        switch mode {
        case .currentDisplay:
            captureCurrentDisplay()
        case .selection:
            beginSelectionCapture()
        }
    }

    private func captureCurrentDisplay() {
        guard let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first else {
            finish(.failure(.noScreenAvailable))
            return
        }

        guard let imageData = captureImageData(on: screen, screenRect: nil) else {
            finish(.failure(.captureFailed))
            return
        }

        finish(.success(imageData))
    }

    private func beginSelectionCapture() {
        teardownSelectionCapture()
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = ScreenshotOverlayWindow(screen: screen) { [weak self] rect, owningScreen in
                self?.handleSelection(rect: rect, on: owningScreen)
            } onCancel: { [weak self] in
                self?.finish(.failure(.userCancelled))
            }
            overlayWindows.append(window)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(.failure(.userCancelled))
                return nil
            }

            return event
        }
    }

    private func handleSelection(rect: CGRect, on screen: NSScreen) {
        teardownSelectionCapture()

        guard rect.width >= 2, rect.height >= 2 else {
            finish(.failure(.userCancelled))
            return
        }

        guard let imageData = captureImageData(on: screen, screenRect: rect) else {
            finish(.failure(.captureFailed))
            return
        }

        finish(.success(imageData))
    }

    private func finish(_ result: Result<Data, NativeScreenshotCaptureError>) {
        teardownSelectionCapture()
        isCapturing = false
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func teardownSelectionCapture() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        overlayWindows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }

    private func captureImageData(on screen: NSScreen, screenRect: CGRect?) -> Data? {
        guard let displayID = screen.aircopyDisplayID else { return nil }

        let cgImage: CGImage?
        if let screenRect {
            let pixelRect = screen.pixelRect(for: screenRect).integral
            guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
            cgImage = CGDisplayCreateImage(displayID, rect: pixelRect)
        } else {
            cgImage = CGDisplayCreateImage(displayID)
        }

        guard let cgImage else { return nil }
        return Self.pngData(from: cgImage)
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
    }

    private static func pngData(from image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

private final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(
        screen: NSScreen,
        onSelection: @escaping (CGRect, NSScreen) -> Void,
        onCancel: @escaping () -> Void
    ) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        let overlayView = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), screen: screen) {
            onSelection($0, screen)
        } onCancel: {
            onCancel()
        }

        contentView = overlayView
    }
}

private final class ScreenshotOverlayView: NSView {
    private let screen: NSScreen
    private let onSelection: (CGRect) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(
        frame frameRect: NSRect,
        screen: NSScreen,
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.onSelection = onSelection
        self.onCancel = onCancel
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.push()
    }

    deinit {
        NSCursor.pop()
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let overlayPath = NSBezierPath(rect: bounds)
        NSColor.black.withAlphaComponent(0.22).setFill()
        overlayPath.fill()

        let selectionRect = currentSelectionRect
        guard !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)
        NSGraphicsContext.current?.restoreGraphicsState()

        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.96).setStroke()
        selectionPath.lineWidth = 1.5
        selectionPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        let selectionRect = currentSelectionRect
        guard !selectionRect.isNull, selectionRect.width > 2, selectionRect.height > 2 else {
            onCancel()
            return
        }

        guard let window else {
            onCancel()
            return
        }

        let screenRect = window.convertToScreen(selectionRect)
        onSelection(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }

        super.keyDown(with: event)
    }

    private var currentSelectionRect: CGRect {
        guard let dragStart, let dragCurrent else { return .null }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }
}

private extension NSScreen {
    var aircopyDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    func pixelRect(for screenRect: CGRect) -> CGRect {
        let scale = backingScaleFactor
        let localMinX = screenRect.minX - frame.minX
        let localMaxY = screenRect.maxY - frame.minY
        let pixelX = localMinX * scale
        let pixelY = (frame.height - localMaxY) * scale
        let pixelWidth = screenRect.width * scale
        let pixelHeight = screenRect.height * scale

        return CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
    }
}
