import AppKit
import CoreText

/// The menu bar icon: a keycap whose face shows the signal. Drawn as a template image on an 18 pt grid,
/// with the same geometry as the design page.
enum KeycapIcon {
    enum Frame: Equatable, Sendable {
        /// A sun.
        case normal
        /// The sun, which the status item dims while signals are off.
        case off
        /// Three dots rolling with the keyboard wave; `phase` runs from 0 to 1 over one breath.
        case thinking(phase: Double)
        /// A question mark; on a lit frame the key fills and the mark is cut out of it.
        case question(lit: Bool)
    }

    static let size = NSSize(width: 18, height: 18)

    static func image(for frame: Frame) -> NSImage {
        let image = NSImage(size: size, flipped: true) { @Sendable _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(frame, in: context)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ frame: Frame, in context: CGContext) {
        context.setFillColor(.black)
        context.setStrokeColor(.black)
        let key = CGPath(roundedRect: CGRect(x: 1.7, y: 1.7, width: 14.6, height: 14.6), cornerWidth: 3.6, cornerHeight: 3.6, transform: nil)
        let lit = frame == .question(lit: true)
        context.addPath(key)
        if lit {
            context.fillPath()
        } else {
            context.setLineWidth(1.4)
            context.strokePath()
        }

        switch frame {
        case .thinking(let phase):
            let angle = 2 * Double.pi * phase
            for i in 0..<3 {
                let wave = sin(angle - Double(i) * 1.1)
                context.setAlpha(0.35 + 0.65 * (0.5 + 0.5 * wave))
                fillDot(in: context, x: 5.6 + Double(i) * 3.4, y: 9.3 - 1.8 * wave, radius: 1.35)
            }
            context.setAlpha(1)
        case .question:
            if lit { context.setBlendMode(.destinationOut) }
            context.addPath(questionMark())
            context.fillPath()
            context.setBlendMode(.normal)
        case .normal, .off:
            fillDot(in: context, x: 9, y: 9, radius: 1.9)
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                context.move(to: CGPoint(x: 9 + cos(angle) * 3.7, y: 9 + sin(angle) * 3.7))
                context.addLine(to: CGPoint(x: 9 + cos(angle) * 5, y: 9 + sin(angle) * 5))
            }
            context.setLineWidth(1.15)
            context.setLineCap(.round)
            context.strokePath()
        }
    }

    private static func fillDot(in context: CGContext, x: Double, y: Double, radius: Double) {
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    /// A bold 11.5 pt "?" centred at x = 9 with its baseline at y = 13.1, in the icon's top-down coordinates.
    private static func questionMark() -> CGPath {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .bold) as CTFont
        var character = UniChar(UInt8(ascii: "?"))
        var glyph = CGGlyph()
        var advance = CGSize.zero
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
              let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { return CGMutablePath() }
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        var placement = CGAffineTransform(translationX: 9 - advance.width / 2, y: 13.1).scaledBy(x: 1, y: -1)
        return outline.copy(using: &placement) ?? outline
    }
}
