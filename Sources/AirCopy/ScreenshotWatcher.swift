import CoreServices
import Foundation

/// Watches the macOS screenshot folder for newly saved screenshot files and
/// reports them. macOS screenshots taken with ⌘⇧4 / ⌘⇧3 are written to a file
/// (not the clipboard), so they otherwise never reach AirCopy's sync path.
///
/// The watcher is deliberately narrow: it only reports image files that look
/// like macOS screenshots (matched by the screenshot filename prefix or the
/// `kMDItemIsScreenCapture` Spotlight attribute), in the configured screenshot
/// directory. It never touches anything else on disk.
final class ScreenshotWatcher {
    /// Emits each newly detected screenshot file. Consume it from the main actor.
    let screenshots: AsyncStream<URL>
    private let continuation: AsyncStream<URL>.Continuation
    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var watchedDirectory: URL?
    private var seen: Set<String> = []
    private let queue = DispatchQueue(label: "dev.aircopy.screenshot-watcher")

    init() {
        (screenshots, continuation) = AsyncStream<URL>.makeStream()
    }

    deinit { stop() }

    func start() {
        stop()
        let dir = Self.screenshotDirectory()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        // Snapshot what's already there so we only react to files added later.
        seen = Self.imageFilenames(in: dir)
        watchedDirectory = dir
        directoryFD = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: queue
        )
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.directoryFD, fd >= 0 { close(fd) }
            self?.directoryFD = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedDirectory = nil
        seen.removeAll()
    }

    private func scan() {
        guard let dir = watchedDirectory else { return }
        let current = Self.imageFilenames(in: dir)
        let added = current.subtracting(seen)
        seen = current
        guard !added.isEmpty else { return }

        for name in added {
            let url = dir.appendingPathComponent(name)
            guard Self.looksLikeScreenshot(url) else { continue }
            // The file may still be flushing when the directory event fires;
            // give it a beat before emitting it.
            let continuation = self.continuation
            queue.asyncAfter(deadline: .now() + 0.35) {
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                continuation.yield(url)
            }
        }
    }

    // MARK: - Helpers

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"]

    private static func imageFilenames(in dir: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return Set(names.filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) })
    }

    /// True when the file is very likely a macOS screenshot: it carries the
    /// `kMDItemIsScreenCapture` Spotlight flag, or its name starts with the
    /// configured screenshot prefix (default "Screenshot").
    private static func looksLikeScreenshot(_ url: URL) -> Bool {
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) {
            if let flag = value as? Bool { return flag }
            if let number = value as? NSNumber { return number.boolValue }
        }
        let prefix = screenshotNamePrefix()
        return url.lastPathComponent.hasPrefix(prefix)
    }

    private static func screencaptureDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "com.apple.screencapture")
    }

    private static func screenshotNamePrefix() -> String {
        let name = screencaptureDefaults()?.string(forKey: "name")
        return (name?.isEmpty == false ? name! : "Screenshot")
    }

    static func screenshotDirectory() -> URL {
        if let location = screencaptureDefaults()?.string(forKey: "location"), !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
        }
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            return desktop
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}
