import AppKit
import SwiftUI

@main
enum GenerateAppIcon {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let context = CGContext(
                    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
                context.translateBy(x: 0, y: 1024)
                context.scaleBy(x: 1, y: -1)
                let background = RoundedRectangle(cornerRadius: 200, style: .continuous)
                    .path(in: CGRect(x: 64, y: 64, width: 896, height: 896)).cgPath
                context.addPath(background)
                context.setFillColor(HarveyTheme.rgb(0x0F0E0D).cgColor)
                context.fillPath()
                context.addPath(background)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
                context.setLineWidth(2)
                context.strokePath()
                context.addPath(Clip20Mark().path(in: CGRect(x: 236, y: 244, width: 552, height: 552)).cgPath)
                context.setFillColor(HarveyTheme.rgb(0xF7F6F4).cgColor)
                context.fillPath()
                let image = NSBitmapImageRep(cgImage: context.makeImage()!)
                let suffix = scale == 2 ? "@2x" : ""
                try image.representation(using: .png, properties: [:])!
                    .write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
