import AppKit
import CryptoKit
import ImageIO

public struct ClipboardEntry: Identifiable {
    public enum Content {
        case text(String)
        case image(data: Data, type: NSPasteboard.PasteboardType, width: Int, height: Int)
    }

    public let id: UUID
    public let content: Content
    public let thumbnail: NSImage?
    public let fingerprint: String
    public let byteCount: Int
    public let capturedAt: Date
    private let sourceFileURL: URL?

    public var text: String? {
        if case .text(let value) = content { return value }
        return nil
    }

    public var isImage: Bool { text == nil }

    public var title: String {
        switch content {
        case .text(let value):
            let preview = String(value.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
            return preview.isEmpty ? "Whitespace" : preview
        case .image:
            return "Image"
        }
    }

    public var detail: String {
        switch content {
        case .text(let value): return "Text · \(value.count.formatted()) characters"
        case .image(_, _, let width, let height): return "Image · \(width) × \(height)"
        }
    }

    public func matches(_ query: String) -> Bool {
        query.isEmpty || (text ?? detail).localizedCaseInsensitiveContains(query)
    }

    public static func text(_ value: String) -> ClipboardEntry? {
        guard !value.isEmpty else { return nil }
        let data = Data(value.utf8)
        guard data.count <= ClipboardHistory.maximumEntryBytes else { return nil }
        return ClipboardEntry(
            id: UUID(), content: .text(value), thumbnail: nil,
            fingerprint: digest(data, prefix: "text"), byteCount: data.count, capturedAt: Date(),
            sourceFileURL: nil
        )
    }

    public static func image(_ data: Data, type: NSPasteboard.PasteboardType) -> ClipboardEntry? {
        image(data, type: type, sourceFileURL: nil)
    }

    private static func image(_ data: Data, type: NSPasteboard.PasteboardType, sourceFileURL: URL?) -> ClipboardEntry? {
        guard !data.isEmpty, data.count <= ClipboardHistory.maximumEntryBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 100_000_000 / height,
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary)
        else { return nil }

        return ClipboardEntry(
            id: UUID(), content: .image(data: data, type: type, width: width, height: height),
            thumbnail: NSImage(cgImage: preview, size: .zero),
            fingerprint: digest(data, prefix: "image:\(type.rawValue)"),
            byteCount: data.count, capturedAt: Date(), sourceFileURL: sourceFileURL
        )
    }

    public static func imageFile(_ data: Data, sourceFileURL: URL? = nil) -> ClipboardEntry? {
        guard data.count <= ClipboardHistory.maximumEntryBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return image(data, type: NSPasteboard.PasteboardType(type as String), sourceFileURL: sourceFileURL)
    }

    public func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        switch content {
        case .text(let value): item.setString(value, forType: .string)
        case .image(let data, let type, _, _):
            // Finder consumes a file URL; image editors consume the saved pixels.
            // Do not offer a missing file or one edited since this history entry was captured.
            if let sourceFileURL, let currentData = try? LocalImageFile.read(sourceFileURL), currentData == data {
                item.setString(sourceFileURL.absoluteString, forType: .fileURL)
            }
            item.setData(data, forType: type)
            if type != .png, let png = Self.pngRepresentation(of: data) {
                item.setData(png, forType: .png)
            }
        }
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        return item
    }

    private static func pngRepresentation(of data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= ClipboardHistory.maximumEntryBytes else { return nil }
        return output as Data
    }

    private static func digest(_ data: Data, prefix: String) -> String {
        prefix + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
