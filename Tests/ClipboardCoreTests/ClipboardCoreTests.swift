import AppKit
import ClipboardCore
import ImageIO

@main
@MainActor
final class ClipboardCoreTests {
    static func main() throws {
        setbuf(stdout, nil)
        let suite = ClipboardCoreTests()
        let checks: [(String, () throws -> Void)] = [
            ("20-item limit", suite.testHistoryRetainsTwentyMostRecentCopies),
            ("Text deduplication", suite.testDuplicateTextMovesToTopWithoutDroppingAnotherEntry),
            ("Empty session on restart", suite.testFreshSessionDoesNotImportExistingClipboard),
            ("Exact Unicode text restoration", suite.testUnicodeWhitespaceAndMultilineTextRoundTripExactly),
            ("Pause / resume", suite.testPauseResumeSkipsCopiesIncludingCopyImmediatelyBeforeResume),
            ("Confidential / transient exclusions", suite.testConfidentialAndTransientCopiesAreExcluded),
            ("PNG / TIFF restoration", suite.testImagesRoundTripWithResolutionAndBytesIntact),
            ("Finder file paste / image paste", suite.testFinderImageRestoresFileAndPixels),
            ("Changed source file fallback", suite.testChangedSourceFileRestoresOnlySavedPixels),
            ("Duplicate image uses latest source file", suite.testDuplicateImageKeepsLatestFileReference),
            ("Finder image capture / independent snapshot", suite.testFinderImageCopyCapturesPixelsAndSurvivesFileRemoval),
            ("Image data with a file reference", suite.testImageWithFileReferenceIsNotDiscarded),
            ("Finder JPEG capture / PNG paste format", suite.testFinderJPEGRestoresStandardPNG),
            ("Native AppKit image paste consumer", suite.testRestoredImagesCanBeReadByAppKit),
            ("Image deduplication / mixed limit", suite.testDuplicateImageAndMixedHistoryLimit),
            ("Clear / delete", suite.testClearAndDeleteDoNotReimportOrEraseSystemClipboard),
            ("Unsupported content", suite.testEmptyMalformedAndFileCopiesAreIgnored),
            ("Text / image search", suite.testSearchMatchesUnicodeTextAndImageMetadata),
            ("Oversized item handling", suite.testOversizedTextIsSkippedWithNotice),
            ("Memory budget", suite.testMemoryBudgetEvictsOldestPayloads),
        ]
        for (name, check) in checks {
            try check()
            print("PASS: \(name)")
        }
        print("All \(checks.count) checks passed. Only isolated test pasteboards were used.")
    }
    @MainActor func testHistoryRetainsTwentyMostRecentCopies() throws {
        let history = ClipboardHistory()
        for number in 1...25 { history.record(try XCTUnwrap(.text("Copy \(number)"))) }
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first?.text, "Copy 25")
        XCTAssertEqual(history.entries.last?.text, "Copy 6")
    }

    @MainActor func testDuplicateTextMovesToTopWithoutDroppingAnotherEntry() throws {
        let history = ClipboardHistory()
        for number in 1...20 { history.record(try XCTUnwrap(.text("Copy \(number)"))) }
        history.record(try XCTUnwrap(.text("Copy 5")))
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first?.text, "Copy 5")
        XCTAssertTrue(history.entries.contains { $0.text == "Copy 1" })
    }

    @MainActor func testFreshSessionDoesNotImportExistingClipboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Copied before launch", forType: .string)
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
        write("Copied after launch", to: board)
        monitor.poll()
        XCTAssertEqual(history.entries.first?.text, "Copied after launch")

        let nextSession = ClipboardHistory()
        ClipboardMonitor(history: nextSession, pasteboard: board).poll()
        XCTAssertTrue(nextSession.entries.isEmpty)
    }

    @MainActor func testUnicodeWhitespaceAndMultilineTextRoundTripExactly() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        let original = "  नमस्ते 👋\n\tlet café = \"☕️\"\n"
        write(original, to: board)
        monitor.poll()
        let entry = try XCTUnwrap(history.entries.first)
        write("Temporary replacement", to: board)
        XCTAssertTrue(monitor.restore(entry))
        XCTAssertEqual(board.string(forType: .string), original)
        monitor.poll()
        XCTAssertEqual(history.entries.count, 1, "Restoring must not recapture our own write")
    }

    @MainActor func testPauseResumeSkipsCopiesIncludingCopyImmediatelyBeforeResume() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        monitor.setPaused(true)
        write("Paused copy", to: board)
        monitor.poll()
        write("Paused copy just before resume", to: board)
        monitor.setPaused(false)
        monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
        write("Resumed copy", to: board)
        monitor.poll()
        XCTAssertEqual(history.entries.map(\.text), ["Resumed copy"])
    }

    @MainActor func testConfidentialAndTransientCopiesAreExcluded() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        // Modern NSPasteboard refuses to create the old non-UTI "Pasteboard generator type".
        for marker in ClipboardMonitor.ignoredTypes where !marker.rawValue.contains(" ") {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setString("Synthetic sensitive content", forType: .string)
            item.setData(Data(), forType: marker)
            board.writeObjects([item])
            monitor.poll()
        }
        XCTAssertTrue(history.entries.isEmpty)
    }

    @MainActor func testImagesRoundTripWithResolutionAndBytesIntact() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        for (format, type) in [(NSBitmapImageRep.FileType.png, NSPasteboard.PasteboardType.png), (.tiff, .tiff)] {
            let data = try imageData(format: format)
            board.clearContents()
            board.setData(data, forType: type)
            monitor.poll()
            let entry = try XCTUnwrap(history.entries.first)
            XCTAssertNotNil(entry.thumbnail)
            guard case .image(let captured, let capturedType, let width, let height) = entry.content else {
                return XCTFail("Image was not captured")
            }
            XCTAssertEqual(width, 320)
            XCTAssertEqual(height, 180)
            XCTAssertEqual(captured, data)
            XCTAssertEqual(capturedType, type)
            write("Replacement", to: board)
            XCTAssertTrue(monitor.restore(entry))
            XCTAssertEqual(board.data(forType: type), data)
        }
    }

    @MainActor func testDuplicateImageAndMixedHistoryLimit() throws {
        let history = ClipboardHistory()
        let data = try imageData()
        let image = try XCTUnwrap(ClipboardEntry.image(data, type: .png))
        history.record(image)
        for number in 1...19 { history.record(try XCTUnwrap(.text("Item \(number)"))) }
        history.record(try XCTUnwrap(.image(data, type: .png)))
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertTrue(try XCTUnwrap(history.entries.first).isImage)
        XCTAssertEqual(history.entries.filter(\.isImage).count, 1)
        history.record(try XCTUnwrap(.text("One more")))
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertFalse(history.entries.contains { $0.text == "Item 1" })
    }

    @MainActor func testFinderImageCopyCapturesPixelsAndSurvivesFileRemoval() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic-image.png")
        let pixels = try imageData()
        try pixels.write(to: file)
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        board.clearContents()
        board.writeObjects([file as NSURL])
        monitor.poll()
        XCTAssertEqual(history.entries.count, 1, "A copied PNG file should appear in history")
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(entry.isImage)
        try FileManager.default.removeItem(at: file)
        write("Replacement", to: board)
        XCTAssertTrue(monitor.restore(entry))
        XCTAssertEqual(board.data(forType: .png), pixels, "History must own the bytes, not depend on the original file")
        XCTAssertTrue(board.string(forType: .fileURL) == nil)
    }

    @MainActor func testFinderImageRestoresFileAndPixels() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Image नमस्ते #1.png")
        let pixels = try imageData()
        try pixels.write(to: file)
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)

        // Exercise both Finder's file-only copy and sources supplying pixels alongside a file.
        for includePixels in [false, true] {
            board.clearContents()
            if includePixels {
                let item = NSPasteboardItem()
                item.setString(file.absoluteString, forType: .fileURL)
                item.setData(pixels, forType: .png)
                XCTAssertTrue(board.writeObjects([item]))
            } else {
                XCTAssertTrue(board.writeObjects([file as NSURL]))
            }
            monitor.poll()
            let entry = try XCTUnwrap(history.entries.first)
            write("Unrelated later copy", to: board)
            XCTAssertTrue(monitor.restore(entry))

            let urls = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true,
            ]) as? [URL])
            XCTAssertEqual(urls, [file], "Restoration must offer a file URL for Finder")
            XCTAssertEqual(board.pasteboardItems?.count, 1, "The file and pixels represent one item")
            XCTAssertEqual(board.data(forType: .png), pixels)
            XCTAssertNotNil(NSImage(pasteboard: board))

            // A file consumer must be able to copy the restored reference into a folder.
            let destination = directory.appendingPathComponent("pasted-\(includePixels).png")
            try FileManager.default.copyItem(at: urls[0], to: destination)
            XCTAssertEqual(try Data(contentsOf: destination), pixels)
            monitor.poll()
            XCTAssertEqual(history.entries.count, 1)
        }
    }

    @MainActor func testChangedSourceFileRestoresOnlySavedPixels() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("edited.png")
        let pixels = try imageData()
        try pixels.write(to: file)
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        board.clearContents()
        board.writeObjects([file as NSURL])
        monitor.poll()
        let entry = try XCTUnwrap(history.entries.first)
        try imageData(format: .jpeg).write(to: file)
        XCTAssertTrue(monitor.restore(entry))
        XCTAssertTrue(board.string(forType: .fileURL) == nil, "Never offer a file with different contents than the captured image")
        XCTAssertEqual(board.data(forType: .png), pixels)
        XCTAssertNotNil(NSImage(pasteboard: board))
    }

    @MainActor func testDuplicateImageKeepsLatestFileReference() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pixels = try imageData()
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        for name in ["first.png", "second.png"] {
            let file = directory.appendingPathComponent(name)
            try pixels.write(to: file)
            board.clearContents()
            board.writeObjects([file as NSURL])
            monitor.poll()
        }
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(monitor.restore(try XCTUnwrap(history.entries.first)))
        XCTAssertEqual(board.string(forType: .fileURL), directory.appendingPathComponent("second.png").absoluteString)
    }

    @MainActor func testImageWithFileReferenceIsNotDiscarded() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        let item = NSPasteboardItem()
        item.setData(try imageData(), forType: .png)
        item.setString("file:///synthetic/does-not-exist.png", forType: .fileURL)
        board.clearContents()
        board.writeObjects([item])
        monitor.poll()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(try XCTUnwrap(history.entries.first).isImage)
    }

    @MainActor func testFinderJPEGRestoresStandardPNG() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("synthetic-image.jpg")
        let pixels = try imageData(format: .jpeg, orientation: 6)
        try pixels.write(to: file)
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        board.clearContents()
        board.writeObjects([file as NSURL])
        monitor.poll()
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(monitor.restore(entry))
        XCTAssertEqual(board.data(forType: .init("public.jpeg")), pixels)
        let png = try XCTUnwrap(board.data(forType: .png))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(decoded.pixelsWide, 180, "PNG must apply the JPEG's 90-degree orientation")
        XCTAssertEqual(decoded.pixelsHigh, 320)
    }

    @MainActor func testClearAndDeleteDoNotReimportOrEraseSystemClipboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        write("First", to: board)
        monitor.poll()
        write("Second", to: board)
        monitor.poll()
        history.remove(try XCTUnwrap(history.entries.last).id)
        XCTAssertEqual(history.entries.map(\.text), ["Second"])
        monitor.clearHistory()
        monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(board.string(forType: .string), "Second")
    }

    @MainActor func testRestoredImagesCanBeReadByAppKit() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        for (format, type) in [
            (NSBitmapImageRep.FileType.png, NSPasteboard.PasteboardType.png),
            (.tiff, .tiff), (.jpeg, .init("public.jpeg")),
        ] {
            let entry = try XCTUnwrap(ClipboardEntry.image(imageData(format: format), type: type))
            history.record(entry)
            XCTAssertTrue(monitor.restore(entry))
            XCTAssertTrue(board.canReadObject(forClasses: [NSImage.self], options: nil))
            let images = try XCTUnwrap(board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])
            XCTAssertEqual(images.count, 1)
            XCTAssertNotNil(images.first?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertNotNil(NSImage(pasteboard: board))
        }
    }

    @MainActor func testEmptyMalformedAndFileCopiesAreIgnored() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        write("", to: board)
        monitor.poll()
        board.clearContents()
        board.setData(Data([0, 1, 2]), forType: .png)
        monitor.poll()
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("file:///synthetic/file.txt", forType: .fileURL)
        item.setString("/synthetic/file.txt", forType: .string)
        board.writeObjects([item])
        monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testSearchMatchesUnicodeTextAndImageMetadata() throws {
        XCTAssertTrue(try XCTUnwrap(ClipboardEntry.text("Hello CAFÉ नमस्ते")).matches("café"))
        XCTAssertTrue(try XCTUnwrap(ClipboardEntry.text("Hello नमस्ते")).matches("नमस्ते"))
        XCTAssertFalse(try XCTUnwrap(ClipboardEntry.text("Hello")).matches("absent"))
        XCTAssertTrue(try XCTUnwrap(ClipboardEntry.image(imageData(), type: .png)).matches("image"))
    }

    @MainActor func testOversizedTextIsSkippedWithNotice() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let history = ClipboardHistory()
        let monitor = ClipboardMonitor(history: history, pasteboard: board)
        write(String(repeating: "x", count: ClipboardHistory.maximumEntryBytes + 1), to: board)
        monitor.poll()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNotNil(monitor.notice)
    }

    @MainActor func testMemoryBudgetEvictsOldestPayloads() throws {
        let history = ClipboardHistory()
        let base = String(repeating: "x", count: ClipboardHistory.maximumEntryBytes - 2)
        for index in 0..<10 { history.record(try XCTUnwrap(.text(base + "\(index)"))) }
        XCTAssertEqual(history.entries.count, 8)
        XCTAssertTrue(try XCTUnwrap(history.entries.first?.text).hasSuffix("9"))
        XCTAssertTrue(try XCTUnwrap(history.entries.last?.text).hasSuffix("2"))
    }

    private func write(_ value: String, to board: NSPasteboard) {
        board.clearContents()
        board.setString(value, forType: .string)
    }

    private func imageData(format: NSBitmapImageRep.FileType = .png, orientation: Int? = nil) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.setColor(NSColor(deviceRed: 0.1, green: 0.4, blue: 0.8, alpha: 1), atX: 10, y: 10)
        let data = try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
        guard let orientation else { return data }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

// Tiny assertion helpers keep the checks runnable with Command Line Tools alone.
// XCTest is distributed with full Xcode, which is not required to build Clip20.
private func XCTAssertTrue(_ value: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true. \(message)", file: file, line: line)
}

private func XCTAssertFalse(_ value: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false. \(message)", file: file, line: line)
}

private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Values differ. \(message)", file: file, line: line)
}

private func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value != nil, "Expected a value", file: file, line: line)
}

private func XCTUnwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { fatalError("Missing expected value", file: file, line: line) }
    return value
}

private func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    preconditionFailure(message, file: file, line: line)
}
