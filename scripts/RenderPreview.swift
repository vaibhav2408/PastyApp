import AppKit
import ClipboardCore
import SwiftUI

/// Renders only this app's view with synthetic content in an invisible window.
/// Does not capture the screen, monitor keys, or read the general clipboard.
@main
@MainActor
enum RenderPreview {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        HarveyTheme.registerFonts(directory: URL(fileURLWithPath: CommandLine.arguments[2]))
        for name in ["HarveySansDiatypeVariable-Regular", "HarveySerif-Regular"] {
            precondition(NSFont(name: name, size: 12) != nil, "Bundled font failed to load: \(name)")
        }
        let history = ClipboardHistory()
        let board = NSPasteboard(name: .init("local.clip20.preview"))
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        let panel = PanelState()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try render("empty", history: history, monitor: monitor, panel: panel, output: output)

        let sampleText = [
            "Remember to bring the presentation adapter",
            "Design review notes\n\nMake the most useful content easiest to scan.",
            "https://example.com/project/overview",
            "git status --short",
            "The quick brown fox jumps over the lazy dog. This is a longer copied paragraph.",
            "Meeting notes\n\nNext steps:\n• Review the draft\n• Share feedback",
            "Hello 👋 — नमस्ते",
            "const greeting = \"Hello, world\";",
        ]
        for text in sampleText.reversed() { history.record(ClipboardEntry.text(text)!) }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        for y in 0..<160 {
            for x in 0..<240 {
                bitmap.setColor(NSColor(deviceRed: CGFloat(x) / 240, green: 0.48,
                                        blue: CGFloat(y) / 160, alpha: 1), atX: x, y: y)
            }
        }
        history.record(ClipboardEntry.image(bitmap.representation(using: .png, properties: [:])!, type: .png)!)
        panel.selectedID = history.entries.dropFirst().first?.id
        try render("history-light", history: history, monitor: monitor, panel: panel, output: output)
        try render("history-dark", history: history, monitor: monitor, panel: panel, output: output, dark: true)
        panel.query = "review"
        try render("search", history: history, monitor: monitor, panel: panel, output: output)
        panel.query = ""
        for index in 1...15 { history.record(ClipboardEntry.text("Additional copy \(index)")!) }
        try render("full-history", history: history, monitor: monitor, panel: panel, output: output)
    }

    private static func render(
        _ name: String, history: ClipboardHistory, monitor: ClipboardMonitor,
        panel: PanelState, output: URL, dark: Bool = false
    ) throws {
        let visibleCount = history.entries.filter { $0.matches(panel.query) }.count
        let size = HistoryLayout.size(entryCount: visibleCount, showsNotice: false)
        let host = NSHostingView(rootView: HistoryView(
            history: history, monitor: monitor, panel: panel, copy: { _ in }, openHistory: {}, quit: {}
        ).environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            fatalError("Cannot allocate preview bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        print("Rendered \(name): \(Int(size.width)) × \(Int(size.height)) points")
        window.close()
    }
}
