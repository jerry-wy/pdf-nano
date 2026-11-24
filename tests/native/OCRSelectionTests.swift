import Foundation
import CoreGraphics
import PDFKit

@main struct OCRSelectionTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func main() throws {
        let data = NSMutableData(); var media = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &media, nil)!
        context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(media)
        context.endPDFPage(); context.closePDF()
        let source = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
        let words = [
            RecognizedWord(text: "WWW", bounds: CGRect(x: 0.1, y: 0.65, width: 0.28, height: 0.06), followingWhitespace: " "),
            RecognizedWord(text: "iii", bounds: CGRect(x: 0.6, y: 0.65, width: 0.04, height: 0.06))
        ]
        let lines = [RecognizedLine(text: "WWW iii", bounds: words[0].bounds.union(words[1].bounds), words: words),
                     RecognizedLine(text: "gyp TOP", bounds: CGRect(x: 0.1, y: 0.4, width: 0.7, height: 0.08))]
        for rotation in [0, 90, 180, 270] {
            let crop = CGRect(x: 20, y: 30, width: 240, height: 340)
            let rendered = try OCRTextLayer.render(source: source.page(at: 1)!, mediaBox: media, cropBox: crop, rotation: rotation, lines: lines)
            let pdf = PDFDocument(data: rendered)!, page = pdf.page(at: 0)!
            page.setBounds(crop, for: .cropBox); page.rotation = rotation
            let geometry = OCRTextLayer.geometry(crop: crop, rotation: rotation)
            for word in words + [RecognizedWord(text: "gyp TOP", bounds: lines[1].bounds)] {
                let found = pdf.findString(word.text, withOptions: [])
                check(found.count == 1, "\(rotation)°: recognized phrase remains searchable exactly once")
                let expected = CGRect(x: word.bounds.minX * geometry.size.width, y: word.bounds.minY * geometry.size.height,
                                      width: word.bounds.width * geometry.size.width, height: word.bounds.height * geometry.size.height).applying(geometry.transform)
                let actual = found[0].bounds(for: page)
                let error = max(abs(actual.minX - expected.minX), abs(actual.minY - expected.minY), abs(actual.maxX - expected.maxX), abs(actual.maxY - expected.maxY))
                if error > 0.25 { print("Expected \(expected), selection \(actual)") }
                check(error <= 0.25, "\(rotation)°: PDFKit selection fits the OCR box within 0.25 pt")
            }
        }
        let chinese = "日本語"
        let chars = Array(chinese).enumerated().map { index, char in
            RecognizedWord(text: String(char), bounds: CGRect(x: 0.1 + Double(index) * 0.1, y: 0.2, width: 0.1, height: 0.07))
        }
        let cjkData = try OCRTextLayer.render(source: source.page(at: 1)!, mediaBox: media, cropBox: media, rotation: 0,
            lines: [RecognizedLine(text: chinese, bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.07), words: chars)])
        let cjk = PDFDocument(data: cjkData)!
        check(cjk.string?.components(separatedBy: .whitespacesAndNewlines).joined().contains(chinese) == true,
              "CJK character targets retain copied Unicode text")
        let sample = "Hello, 世界 🙂 café"
        check(OCRRecognition.ranges(in: sample).map { String(sample[$0]) } == ["Hello,", "世", "界", "🙂", "café"],
              "Word segmentation retains punctuation, Unicode and grapheme boundaries")
        let multi = PDFDocument()
        for (index, text) in ["Existing searchable page", "Needle on first scanned page", "Needle on second scanned page"].enumerated() {
            let rendered = try OCRTextLayer.render(source: source.page(at: 1)!, mediaBox: media, cropBox: media, rotation: 0,
                lines: [RecognizedLine(text: text, bounds: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.08))])
            let generated = PDFDocument(data: rendered)!
            let copied = generated.page(at: 0)!.copy() as! PDFPage
            multi.insert(copied, at: index)
        }
        let saved = PDFDocument(data: multi.dataRepresentation()!)!
        check(saved.findString("Needle", withOptions: []).count == 2 && saved.page(at: 0)!.string!.contains("Existing"),
              "OCR text is searchable across all scanned pages after saving, alongside existing text")
        let bitmap = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(media)
        let rebuilt = try OCRTextLayer.render(source: saved.page(at: 0)!.pageRef!, mediaBox: media, cropBox: media, rotation: 0,
            lines: [RecognizedLine(text: "Repaired", bounds: CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.08))], replacingTextWith: bitmap.makeImage()!)
        let repaired = PDFDocument(data: rebuilt)!
        check(repaired.findString("Existing", withOptions: []).isEmpty && repaired.findString("Repaired", withOptions: []).count == 1,
              "Rebuilding replaces the old invisible layer without duplicate selectable text")
    }
}
