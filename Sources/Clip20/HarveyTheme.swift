import AppKit
import CoreText
import SwiftUI

// Adapted from frontend/packages/design-system/src/tokens/css/tokens.reskin.*.css.
enum HarveyTheme {
    static let background = color(light: 0xFFFFFF, dark: 0x0F0E0D)
    static let raised = color(light: 0xF7F6F4, dark: 0x1A1917)
    static let text = color(light: 0x1A1917, dark: 0xE4E1DD)
    static let subtle = color(light: 0x6A6660, dark: 0x9E9B95)
    static let border = color(light: 0xE2DFDA, dark: 0x363431)
    static let selected = color(light: 0xE7E4DE, dark: 0x33312C)
    static let hovered = color(light: 0xF3F2F0, dark: 0x25231F)
    static let chrome = Color(nsColor: rgb(0x0F0E0D))
    static let chromeText = Color(nsColor: rgb(0xF7F6F4))
    static let chromeSubtle = Color(nsColor: rgb(0xB8B5B0))

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("HarveySansDiatypeVariable-Regular", fixedSize: size).weight(weight)
    }

    static func serif(_ size: CGFloat) -> Font {
        .custom("HarveySerif-Regular", fixedSize: size)
    }

    static func registerFonts(directory: URL? = nil) {
        #if SWIFT_PACKAGE
        let resources = Bundle.module.resourceURL
        #else
        let resources = Bundle.main.resourceURL
        #endif
        guard let directory = directory ?? resources?.appendingPathComponent("Fonts") else { return }
        for name in ["HarveySansDiatypeVariable.ttf", "HarveySerif-Regular.ttf"] {
            CTFontManagerRegisterFontsForURL(directory.appendingPathComponent(name) as CFURL, .process, nil)
        }
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(Clip20Mark().path(in: CGRect(x: 1, y: 1, width: 16, height: 16)).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clip20 clipboard history"
        return image
    }

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct Clip20Mark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 77, y: 14))
        path.addCurve(to: CGPoint(x: 44, y: 2), control1: CGPoint(x: 68, y: 6), control2: CGPoint(x: 57, y: 2))
        path.addCurve(to: CGPoint(x: 2, y: 44), control1: CGPoint(x: 21, y: 2), control2: CGPoint(x: 2, y: 21))
        path.addCurve(to: CGPoint(x: 44, y: 86), control1: CGPoint(x: 2, y: 67), control2: CGPoint(x: 21, y: 86))
        path.addCurve(to: CGPoint(x: 66, y: 80), control1: CGPoint(x: 52, y: 86), control2: CGPoint(x: 60, y: 84))
        path.addLine(to: CGPoint(x: 58, y: 69))
        path.addCurve(to: CGPoint(x: 44, y: 73), control1: CGPoint(x: 54, y: 72), control2: CGPoint(x: 49, y: 73))
        path.addCurve(to: CGPoint(x: 15, y: 44), control1: CGPoint(x: 28, y: 73), control2: CGPoint(x: 15, y: 60))
        path.addCurve(to: CGPoint(x: 44, y: 15), control1: CGPoint(x: 15, y: 28), control2: CGPoint(x: 28, y: 15))
        path.addCurve(to: CGPoint(x: 68, y: 24), control1: CGPoint(x: 53, y: 15), control2: CGPoint(x: 62, y: 18))
        path.closeSubpath()
        path.addPath(HarveyMark().path(in: CGRect(x: 70, y: 69, width: 28, height: 24.5)))
        return path.applying(CGAffineTransform(a: rect.width / 100, b: 0, c: 0, d: rect.height / 100,
                                               tx: rect.minX, ty: rect.minY))
    }
}

// Exact vector geometry from frontend/packages/design-system/src/icons/harvey-logo.tsx.
struct HarveyMark: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (32, 28), (18, 28), (22, 24), (22, 15.6), (10, 15.6), (10, 24),
            (14, 28), (0, 28), (4, 24), (4, 4), (0, 0), (14, 0), (10, 4),
            (10, 11.6), (22, 11.6), (22, 4), (18, 0), (32, 0), (28, 4), (28, 24),
        ]
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.0 / 32 * rect.width,
                                           y: rect.minY + $0.1 / 28 * rect.height) })
        path.closeSubpath()
        return path
    }
}
