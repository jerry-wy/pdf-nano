import Foundation
import CoreGraphics
import CoreText

struct RecognizedWord {
    let text: String
    let bounds: CGRect
    var followingWhitespace = ""
}

struct RecognizedLine {
    let text: String
    // Normalized upright image coordinates from Vision.
    let bounds: CGRect
    var words: [RecognizedWord] = []
}

enum OCRTextLayer {
    static func geometry(crop: CGRect, rotation: Int) -> (transform: CGAffineTransform, size: CGSize) {
        switch ((rotation % 360) + 360) % 360 {
        case 90:
            return (CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: crop.maxX, ty: crop.minY), CGSize(width: crop.height, height: crop.width))
        case 180:
            return (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: crop.maxX, ty: crop.maxY), crop.size)
        case 270:
            return (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: crop.minX, ty: crop.maxY), CGSize(width: crop.height, height: crop.width))
        default:
            return (CGAffineTransform(translationX: crop.minX, y: crop.minY), crop.size)
        }
    }

    static func render(source: CGPDFPage, mediaBox: CGRect, cropBox: CGRect, rotation: Int, lines: [RecognizedLine], replacingTextWith image: CGImage? = nil) throws -> Data {
        let data = NSMutableData()
        var media = mediaBox
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw ocrError("Could not create a selectable text layer.")
        }
        context.beginPDFPage(nil)
        // Copy the original page content without rasterizing or burning in its
        // annotations; editable annotation copies are restored below.
        let geometry = geometry(crop: cropBox, rotation: rotation)
        if let image {
            context.saveGState(); context.concatenate(geometry.transform)
            context.draw(image, in: CGRect(origin: .zero, size: geometry.size))
            context.restoreGState()
        } else { context.drawPDFPage(source) }
        func draw(_ value: String, in bounds: CGRect) {
            guard !value.isEmpty, bounds.width > 0, bounds.height > 0,
                  [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ $0.isFinite }) else { return }
            let box = CGRect(x: bounds.minX * geometry.size.width, y: bounds.minY * geometry.size.height,
                             width: bounds.width * geometry.size.width, height: bounds.height * geometry.size.height)
            let base = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let font = CTFontCreateForString(base, value as CFString, CFRange(location: 0, length: (value as NSString).length))
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let text = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let advance = CGFloat(CTLineGetTypographicBounds(text, &ascent, &descent, nil))
            let height = ascent + descent
            guard advance > 0, height > 0 else { return }
            context.saveGState()
            context.concatenate(geometry.transform)
            context.translateBy(x: box.minX, y: box.minY)
            context.scaleBy(x: box.width / advance, y: box.height / height)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 0, y: descent)
            context.setTextDrawingMode(.invisible)
            CGPDFContextBeginTag(context, .span, [CGPDFTagProperty.actualText.rawValue: value] as CFDictionary)
            CTLineDraw(text, context)
            CGPDFContextEndTag(context)
            context.restoreGState()
        }
        for line in lines {
            if line.words.isEmpty { draw(line.text, in: line.bounds); continue }
            for (index, word) in line.words.enumerated() {
                draw(word.text, in: word.bounds)
                if !word.followingWhitespace.isEmpty, index + 1 < line.words.count {
                    let next = line.words[index + 1]
                    let gap = next.bounds.minX - word.bounds.maxX
                    if gap > 0 {
                        draw(word.followingWhitespace, in: CGRect(x: word.bounds.maxX, y: word.bounds.minY, width: gap, height: word.bounds.height))
                    }
                }
            }
        }
        context.endPDFPage(); context.closePDF()
        return data as Data
    }
    private static func ocrError(_ message: String) -> NSError {
        NSError(domain: "PDFNano", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
