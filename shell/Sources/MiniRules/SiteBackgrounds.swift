public struct SiteBackgrounds: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let host: String
        public let rgb: UInt32
    }

    public private(set) var entries: [Entry] = []
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public static func opaqueRGB(fromPacked rgba: UInt32) -> UInt32? {
        rgba & 0xff == 0xff ? rgba >> 8 : nil
    }

    public func rgb(forHost host: String) -> UInt32? {
        entries.last { $0.host == host }?.rgb
    }

    @discardableResult
    public mutating func record(_ rgb: UInt32, forHost host: String) -> Bool {
        if entries.last?.host == host, entries.last?.rgb == rgb { return false }
        entries.removeAll { $0.host == host }
        entries.append(Entry(host: host, rgb: rgb))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        return true
    }
}
