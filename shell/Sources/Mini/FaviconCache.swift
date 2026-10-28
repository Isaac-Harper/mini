import AppKit
import CryptoKit

@MainActor
final class FaviconCache {
    private let directory: URL
    private var imagesByHost: [String: NSImage] = [:]
    private var missingHosts: Set<String> = []
    private let writer = DispatchQueue(label: "Mini.FaviconCache", qos: .utility)

    private static let maximumFiles = 500

    init(directory: URL) {
        self.directory = directory.appendingPathComponent("Favicons")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create favicon cache \(self.directory.path): \(error)")
        }
    }

    static func image(fromPNG pngData: Data) -> NSImage? {
        guard !pngData.isEmpty, let image = NSImage(data: pngData) else { return nil }
        image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
        return image
    }

    func store(_ pngData: Data, image: NSImage, forPageAt address: String) {
        guard let host = SitePreferences.host(of: address) else { return }
        imagesByHost[host] = image
        missingHosts.remove(host)
        let fileURL = file(for: host)
        writer.async {
            if (try? Data(contentsOf: fileURL)) == pngData { return }
            try? pngData.write(to: fileURL, options: .atomic)
        }
    }

    func image(forPageAt address: String) -> NSImage? {
        guard let host = SitePreferences.host(of: address), !missingHosts.contains(host) else { return nil }
        if let image = imagesByHost[host] { return image }
        guard let data = try? Data(contentsOf: file(for: host)), let image = Self.image(fromPNG: data) else {
            missingHosts.insert(host)
            return nil
        }
        imagesByHost[host] = image
        return image
    }

    func prune(keepingPagesAt addresses: [String]) {
        let keptFiles = Set(addresses.compactMap(SitePreferences.host(of:)).map { file(for: $0).lastPathComponent })
        let directory = self.directory
        let maximumFiles = Self.maximumFiles
        writer.async {
            let manager = FileManager.default
            guard let files = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            var remaining: [(url: URL, modified: Date)] = []
            for file in files {
                if keptFiles.contains(file.lastPathComponent) {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    remaining.append((file, modified ?? .distantPast))
                } else {
                    try? manager.removeItem(at: file)
                }
            }
            for stale in remaining.sorted(by: { $0.modified > $1.modified }).dropFirst(maximumFiles) {
                try? manager.removeItem(at: stale.url)
            }
        }
    }

    func fileURL(forPageAt address: String) -> URL? {
        SitePreferences.host(of: address).map(file(for:))
    }

    private func file(for host: String) -> URL {
        let digest = SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).png")
    }
}
