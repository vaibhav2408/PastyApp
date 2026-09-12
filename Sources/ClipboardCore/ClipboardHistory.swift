import Combine
import Foundation

/// Session-only storage. No serialization, preferences, or file I/O.
@MainActor
public final class ClipboardHistory: ObservableObject {
    public nonisolated static let capacity = 20
    public nonisolated static let maximumEntryBytes = 32 * 1_024 * 1_024
    public nonisolated static let maximumHistoryBytes = 256 * 1_024 * 1_024

    @Published public private(set) var entries: [ClipboardEntry] = []

    public init() {}

    public func record(_ entry: ClipboardEntry) {
        entries.removeAll { $0.fingerprint == entry.fingerprint }
        entries.insert(entry, at: 0)
        var totalBytes = 0
        entries = Array(entries.prefix(Self.capacity).prefix { candidate in
            totalBytes += candidate.byteCount
            return totalBytes <= Self.maximumHistoryBytes
        })
    }

    public func promote(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
    }

    public func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public func clear() { entries.removeAll() }
}
