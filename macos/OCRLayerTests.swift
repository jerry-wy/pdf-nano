import Foundation
import CoreGraphics

@main struct OCRCheck {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let original = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = CGContext(consumer: CGDataConsumer(data: original as CFMutableData)!, mediaBox: &media, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fill(media)
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 20, y: 30, width: 80, height: 40))
        context.endPDFPage(); context.closePDF()
        try (original as Data).write(to: output.appendingPathComponent("original.pdf"))
        let document = CGPDFDocument(CGDataProvider(data: original as CFData)!)!
        let lines = [RecognizedLine(text: "Selectable OCR text", bounds: CGRect(x: 0.1, y: 0.6, width: 0.7, height: 0.08)),
                     RecognizedLine(text: "Second line", bounds: CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.06)),
                     RecognizedLine(text: "日本語 OCR", bounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.06))]
        for rotation in [0, 90, 180, 270] {
            let data = try OCRTextLayer.render(source: document.page(at: 1)!, mediaBox: media, cropBox: media, rotation: rotation, lines: lines)
            try data.write(to: output.appendingPathComponent("ocr-\(rotation).pdf"))
        }
        let cropped = try OCRTextLayer.render(source: document.page(at: 1)!, mediaBox: media,
                                               cropBox: CGRect(x: 20, y: 30, width: 240, height: 340), rotation: 90, lines: lines)
        try cropped.write(to: output.appendingPathComponent("ocr-cropped-90.pdf"))
        print("PASS: Core Graphics renders OCR text layers at all four page rotations")
    }
}
