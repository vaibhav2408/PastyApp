import Foundation

/// Bounded, local-only reads shared by capture and file-reference validation.
enum LocalImageFile {
    enum ReadError: Error {
        case unsupported, unavailableLocally, tooLarge
    }

    static func read(_ sourceURL: URL) throws -> Data {
        guard sourceURL.isFileURL else { throw ReadError.unsupported }
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        var url = sourceURL
        url.removeAllCachedResourceValues()
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .volumeIsLocalKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ])
        guard values.isRegularFile == true else { throw ReadError.unsupported }
        guard values.volumeIsLocal != false,
              values.ubiquitousItemDownloadingStatus != .notDownloaded else {
            throw ReadError.unavailableLocally
        }
        if let size = values.fileSize, size > ClipboardHistory.maximumEntryBytes {
            throw ReadError.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: ClipboardHistory.maximumEntryBytes + 1) else {
            throw ReadError.unsupported
        }
        guard data.count <= ClipboardHistory.maximumEntryBytes else { throw ReadError.tooLarge }
        return data
    }
}
