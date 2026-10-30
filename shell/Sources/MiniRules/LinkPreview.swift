import Foundation

public struct LinkPreviewTags: Equatable, Sendable {
    public var baseURL: String
    public var titleTag: String
    public var openGraphTitle: String
    public var twitterTitle: String
    public var openGraphDescription: String
    public var twitterDescription: String
    public var description: String
    public var openGraphImage: String
    public var twitterImage: String
    public var declaredImageWidth: Int
    public var declaredImageHeight: Int

    public init(baseURL: String, titleTag: String = "", openGraphTitle: String = "", twitterTitle: String = "", openGraphDescription: String = "",
                twitterDescription: String = "", description: String = "", openGraphImage: String = "", twitterImage: String = "",
                declaredImageWidth: Int = 0, declaredImageHeight: Int = 0) {
        self.baseURL = baseURL
        self.titleTag = titleTag
        self.openGraphTitle = openGraphTitle
        self.twitterTitle = twitterTitle
        self.openGraphDescription = openGraphDescription
        self.twitterDescription = twitterDescription
        self.description = description
        self.openGraphImage = openGraphImage
        self.twitterImage = twitterImage
        self.declaredImageWidth = declaredImageWidth
        self.declaredImageHeight = declaredImageHeight
    }
}

public struct LinkPreview: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var imageURL: URL?
    public var declaredImageSize: CGSize?

    public init(_ tags: LinkPreviewTags) {
        title = Self.first(tags.openGraphTitle, tags.twitterTitle, tags.titleTag)
        description = Self.first(tags.openGraphDescription, tags.twitterDescription, tags.description)
        let base = URL(string: tags.baseURL)
        imageURL = [tags.openGraphImage, tags.twitterImage].lazy.compactMap { Self.resolve($0, against: base) }.first
        declaredImageSize = tags.declaredImageWidth > 0 && tags.declaredImageHeight > 0
            ? CGSize(width: tags.declaredImageWidth, height: tags.declaredImageHeight) : nil
    }

    private static func first(_ values: String...) -> String? {
        values.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    public static func resolve(_ reference: String, against base: URL?) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }

    public static let commonAspect = 1.91
    public static let acceptedAspects = 1.7...2.1

    public static func aspectWarning(for size: CGSize) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        let aspect = size.width / size.height
        guard !acceptedAspects.contains(aspect) else { return nil }
        return "Image is \(ratioText(aspect)), most apps crop to 1.91:1"
    }

    public static func ratioText(_ aspect: Double) -> String {
        let named: [(Double, String)] = [(1, "1:1"), (4.0 / 3, "4:3"), (3.0 / 2, "3:2"), (16.0 / 9, "16:9"), (2, "2:1"), (21.0 / 9, "21:9"),
                                         (3.0 / 4, "3:4"), (2.0 / 3, "2:3"), (9.0 / 16, "9:16"), (4.0 / 5, "4:5"), (5.0 / 4, "5:4")]
        if let match = named.first(where: { abs($0.0 - aspect) / $0.0 < 0.02 }) { return match.1 }
        return aspect >= 1 ? String(format: "%.2f:1", aspect) : String(format: "1:%.2f", 1 / aspect)
    }

    public enum ImageState: Equatable, Sendable {
        case pending
        case loaded(CGSize)
        case failed
    }

    public func diagnostic(image: ImageState) -> String? {
        guard imageURL != nil else { return "No preview image" }
        switch image {
        case .failed:
            return "Preview image did not load"
        case .loaded(let size):
            if let warning = Self.aspectWarning(for: size) { return warning }
        case .pending:
            if let size = declaredImageSize, let warning = Self.aspectWarning(for: size) { return warning }
        }
        return title == nil ? "No title tag" : nil
    }
}
