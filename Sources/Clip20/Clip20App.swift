import AppKit
import ClipboardCore
import Combine
import SwiftUI

@main
enum Clip20App {
    @MainActor static func main() {
        HarveyTheme.registerFonts()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private let history = ClipboardHistory()
    private lazy var monitor = ClipboardMonitor(history: history)
    private let panel = PanelState()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var keyboardMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid multiple status icons if the binary is launched directly more than once.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        installApplicationMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = HarveyTheme.menuBarImage()
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Clip20 — clipboard history (⌃⌥V)"
            button.setAccessibilityLabel("Clip20 clipboard history")
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = HistoryLayout.size(entryCount: 0, showsNotice: false)
        popover.contentViewController = NSHostingController(rootView: HistoryView(
            history: history, monitor: monitor, panel: panel,
            copy: { [weak self] in self?.copy($0) },
            openHistory: { [weak self] in self?.openHistoryFromMenu() },
            quit: { NSApp.terminate(nil) }
        ))

        hotKey = GlobalHotKey { [weak self] in self?.toggleHistory() }
        panel.shortcutAvailable = hotKey != nil
        history.$entries.combineLatest(panel.$query, monitor.$isPaused, monitor.$notice)
            .sink { [weak self] entries, query, paused, notice in
                guard let self else { return }
                let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
                self.popover.contentSize = HistoryLayout.size(
                    entryCount: entries.filter { $0.matches(query) }.count,
                    showsNotice: paused || notice != nil || !self.panel.shortcutAvailable
                )
            }.store(in: &subscriptions)
        monitor.$isPaused.sink { [weak self] paused in
            self?.statusItem.button?.image = paused
                ? NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Clip20 capture paused")
                : HarveyTheme.menuBarImage()
            self?.statusItem.button?.image?.isTemplate = true
        }.store(in: &subscriptions)
        monitor.start()

        if ProcessInfo.processInfo.arguments.contains("--show-history") {
            DispatchQueue.main.async { [weak self] in self?.toggleHistory() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        monitor.clearHistory()
        removeKeyboardMonitor()
    }

    private func installApplicationMenu() {
        // Standard responder-chain actions make Command-A/C/V work in the search field.
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Clip20")
        applicationMenu.addItem(withTitle: "Quit Clip20", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleHistory() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showHistory()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showOptionsMenu()
        } else {
            toggleHistory()
        }
    }

    private func rememberPreviousApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
    }

    private func showOptionsMenu() {
        guard let button = statusItem.button else { return }
        rememberPreviousApp()
        popover.performClose(nil)
        removeKeyboardMonitor()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let pause = NSMenuItem(title: monitor.isPaused ? "Resume capture" : "Pause capture",
                               action: #selector(toggleCapture), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear history", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !history.entries.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open history", action: #selector(openHistoryFromMenu), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.control, .option]
        open.target = self
        menu.addItem(open)

        let note = NSMenuItem(title: "History clears when you quit", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Clip20", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        // Use the status item's native menu anchoring, then restore normal left-click behavior.
        statusItem.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        if statusItem.menu === menu { statusItem.menu = nil }
    }

    @objc private func toggleCapture() { monitor.setPaused(!monitor.isPaused) }
    @objc private func clearHistory() { monitor.clearHistory() }

    @objc private func openHistoryFromMenu() {
        // Let menu tracking finish before showing/focusing the popover.
        DispatchQueue.main.async { [weak self] in self?.showHistory() }
    }

    private func showHistory() {
        guard let button = statusItem.button else { return }
        rememberPreviousApp()
        panel.query = ""
        panel.selectedID = history.entries.first?.id
        panel.presentation = UUID()
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
        installKeyboardMonitor()
    }

    private func copy(_ entry: ClipboardEntry) {
        guard monitor.restore(entry) else { return }
        popover.performClose(nil)
        // Restore focus so the user's next Command-V goes to the original app.
        previousApp?.activate(options: [])
    }

    func popoverDidClose(_ notification: Notification) { removeKeyboardMonitor() }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let entries = history.entries.filter {
            $0.matches(panel.query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if event.keyCode == 53 { // Escape
            popover.performClose(nil)
            previousApp?.activate(options: [])
            return true
        }
        if modifiers == .command, event.keyCode == 51, let id = panel.selectedID {
            history.remove(id)
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125, 126: // Down / Up
            guard !entries.isEmpty else { return true }
            let index = entries.firstIndex { $0.id == panel.selectedID } ?? 0
            let next = min(max(index + (event.keyCode == 125 ? 1 : -1), 0), entries.count - 1)
            panel.selectedID = entries[next].id
            return true
        case 36, 76: // Return / keypad Enter
            if let entry = entries.first(where: { $0.id == panel.selectedID }) ?? entries.first { copy(entry) }
            return true
        default:
            return false
        }
    }
}
