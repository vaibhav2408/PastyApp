import AppKit
import ClipboardCore
import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var presentation = UUID()
    @Published var shortcutAvailable = true
}

enum HistoryLayout {
    static let width: CGFloat = 340
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 1
    static let maximumVisibleRows = 10

    static func listHeight(entryCount: Int) -> CGFloat {
        guard entryCount > 0 else { return 112 }
        let rows = CGFloat(min(entryCount, maximumVisibleRows))
        return rows * rowHeight + (rows - 1) * rowSpacing + 6
    }

    static func size(entryCount: Int, showsNotice: Bool) -> NSSize {
        // Toolbar, search, list, optional status, and keyboard hints.
        NSSize(width: width, height: 30 + 40 + listHeight(entryCount: entryCount) + (showsNotice ? 34 : 0) + 26)
    }
}

struct HistoryView: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var panel: PanelState
    let copy: (ClipboardEntry) -> Void
    let openHistory: () -> Void
    let quit: () -> Void
    @FocusState private var searchFocused: Bool

    private var visibleEntries: [ClipboardEntry] {
        history.entries.filter { $0.matches(panel.query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private var showsNotice: Bool {
        monitor.isPaused || monitor.notice != nil || !panel.shortcutAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            search
            if visibleEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: HistoryLayout.rowSpacing) {
                            ForEach(visibleEntries) { entry in
                                HistoryRow(entry: entry, selected: panel.selectedID == entry.id,
                                           copy: { copy(entry) }, delete: { history.remove(entry.id) })
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                    }
                    .frame(height: HistoryLayout.listHeight(entryCount: visibleEntries.count))
                    .onChange(of: panel.selectedID) { id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            if showsNotice {
                Label(monitor.notice ?? (monitor.isPaused
                    ? "Paused. Existing copies are still available."
                    : "Shortcut in use. Open from the menu bar."),
                      systemImage: monitor.isPaused ? "pause.circle" : "info.circle")
                    .font(HarveyTheme.sans(10)).foregroundStyle(HarveyTheme.subtle).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).frame(height: 34)
            }

            HarveyTheme.border.frame(height: 1)
            HStack(spacing: 10) {
                Text("↑↓ Select")
                Text("↵ Copy")
                Spacer()
                Text("⌘V Paste")
            }
            .font(HarveyTheme.sans(10)).foregroundStyle(HarveyTheme.subtle)
            .padding(.horizontal, 12).frame(height: 25)
            .background(HarveyTheme.raised)
        }
        .frame(width: HistoryLayout.width)
        .background(HarveyTheme.background)
        .foregroundStyle(HarveyTheme.text)
        .tint(HarveyTheme.text)
        .font(HarveyTheme.sans(12))
        .onAppear { searchFocused = true }
        .onChange(of: panel.presentation) { _ in searchFocused = true }
        .onChange(of: panel.query) { _ in panel.selectedID = visibleEntries.first?.id }
        .onChange(of: history.entries.map(\.id)) { _ in
            if !visibleEntries.contains(where: { $0.id == panel.selectedID }) {
                panel.selectedID = visibleEntries.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Clip20Mark().fill(HarveyTheme.chromeText).frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text("Clip20").font(HarveyTheme.serif(15)).foregroundStyle(HarveyTheme.chromeText)
            Text(panel.query.isEmpty ? "\(history.entries.count)/20" : "\(visibleEntries.count) found")
                .font(HarveyTheme.sans(10)).monospacedDigit().foregroundStyle(HarveyTheme.chromeSubtle)
            Spacer()
            Menu {
                Button(monitor.isPaused ? "Resume capture" : "Pause capture") {
                    monitor.setPaused(!monitor.isPaused)
                }
                Button("Clear history", role: .destructive) { monitor.clearHistory() }
                    .disabled(history.entries.isEmpty)
                Divider()
                Button("Open history", action: openHistory)
                    .keyboardShortcut("v", modifiers: [.control, .option])
                Text("History clears when you quit")
                Divider()
                Button("Quit Clip20", action: quit)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HarveyTheme.chromeSubtle).frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .environment(\.colorScheme, .dark)
            .accessibilityLabel("Clip20 options")
        }
        .padding(.leading, 12).padding(.trailing, 7).frame(height: 30)
        .background(HarveyTheme.chrome)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(HarveyTheme.subtle)
            TextField("", text: $panel.query, prompt: Text("Search history").foregroundColor(HarveyTheme.subtle))
                .textFieldStyle(.plain).font(HarveyTheme.sans(12))
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
            if !panel.query.isEmpty {
                Button { panel.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(HarveyTheme.subtle).accessibilityLabel("Clear search")
            } else if panel.shortcutAvailable {
                Text("⌃⌥V").font(HarveyTheme.sans(10)).foregroundStyle(HarveyTheme.subtle)
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(HarveyTheme.raised, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? HarveyTheme.subtle : HarveyTheme.border))
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: panel.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 22, weight: .light)).foregroundStyle(HarveyTheme.subtle)
            Text(panel.query.isEmpty ? "Ready when you copy" : "No matching copies")
                .font(HarveyTheme.serif(15))
            Text(panel.query.isEmpty
                 ? "Copy text or an image in any app to start."
                 : "Try another word, or clear your search.")
                .font(HarveyTheme.sans(11)).foregroundStyle(HarveyTheme.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: HistoryLayout.listHeight(entryCount: 0))
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry
    let selected: Bool
    let copy: () -> Void
    let delete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: copy) {
                HStack(spacing: 8) {
                    Group {
                        if let thumbnail = entry.thumbnail {
                            Image(nsImage: thumbnail).resizable().scaledToFit()
                        } else {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 12, weight: .regular)).foregroundStyle(HarveyTheme.subtle)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    if entry.isImage {
                        Text(entry.detail).font(HarveyTheme.sans(12)).lineLimit(1)
                    } else {
                        Text(entry.title.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                            .font(HarveyTheme.sans(12)).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: HistoryLayout.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isImage ? entry.detail : "Copy \(entry.title)")
            .help(entry.text.map { String($0.prefix(1_200)) } ?? entry.detail)
            Button(action: delete) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HarveyTheme.subtle).frame(width: 22, height: HistoryLayout.rowHeight)
            }
            .buttonStyle(.plain).opacity(hovered || selected ? 1 : 0)
            .accessibilityLabel("Delete item").help("Delete from history")
        }
        .padding(.leading, 6).padding(.trailing, 2)
        .background(selected ? HarveyTheme.selected : (hovered ? HarveyTheme.hovered : .clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete from history", role: .destructive, action: delete)
        }
    }
}
