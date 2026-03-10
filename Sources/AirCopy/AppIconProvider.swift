import AppKit
import Foundation

enum AppIconProvider {
    static func loadAppIcon() -> NSImage? {
        let fileManager = FileManager.default
        let searchPaths: [String?] = [
            Bundle.main.resourceURL?.appendingPathComponent("AirCopy.icns").path,
            Bundle.main.resourceURL?.appendingPathComponent("512.png").path,
            Bundle.main.resourceURL?.appendingPathComponent("256.png").path,
            fileManager.currentDirectoryPath + "/Resources/AirCopy.icns",
            fileManager.currentDirectoryPath + "/Resources/512.png",
            fileManager.currentDirectoryPath + "/Resources/256.png",
            fileManager.currentDirectoryPath + "/dist/AirCopy.icns"
        ]

        for path in searchPaths.compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: path), let image = NSImage(contentsOfFile: path) else {
                continue
            }
            return image
        }

        return nil
    }
}
