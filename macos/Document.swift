import AppKit
import PDFKit

@objc(NanoDocument)
final class NanoDocument: NSDocument {
    var pdf = PDFDocument()

    override class var autosavesInPlace: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let loaded = PDFDocument(data: data), !loaded.isLocked else {
            throw NSError(domain: "PDFNano", code: 1, userInfo: [NSLocalizedDescriptionKey: "This PDF cannot be opened. It may be damaged or password protected."])
        }
        pdf = loaded
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = pdf.dataRepresentation() else {
            throw NSError(domain: "PDFNano", code: 2, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be saved."])
        }
        return data
    }

    override func makeWindowControllers() {
        addWindowController(ReaderController(document: self))
    }
}

// Annotations and scans use PDFKit's own format, and remain editable in other PDF apps.
enum PDFOperations {
    static func highlight(_ selection: PDFSelection) -> [(PDFPage, PDFAnnotation)] {
        selection.selectionsByLine().flatMap { line in
            line.pages.compactMap { page -> (PDFPage, PDFAnnotation)? in
                let rect = line.bounds(for: page)
                guard !rect.isEmpty, !rect.isInfinite else { return nil }
                let mark = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                mark.color = NSColor.systemYellow.withAlphaComponent(0.4)
                return (page, mark)
            }
        }
    }

    static func scan(_ urls: [URL]) throws -> PDFDocument {
        let result = PDFDocument()
        for url in urls {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                throw NSError(domain: "PDFNano", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read \(url.lastPathComponent). Choose a supported image file."])
            }
            result.insert(page, at: result.pageCount)
        }
        return result
    }
}

// OCR replaces only page content; the original document and editable annotations
// remain in the normal save and undo lifecycle.
extension PDFOperations {
    static func ocrTransform(for page: PDFPage) -> (transform: CGAffineTransform, size: CGSize) {
        OCRTextLayer.geometry(crop: page.bounds(for: .cropBox), rotation: page.rotation)
    }
    static func recognizedPage(_ original: PDFPage, lines: [RecognizedLine], replacingTextWith image: CGImage? = nil) throws -> PDFPage {
        // Image-import pages may not have a CGPDFPage until serialized once.
        let snapshot = PDFDocument()
        if let copy = original.copy() as? PDFPage { snapshot.insert(copy, at: 0) }
        let serialized = original.pageRef == nil ? snapshot.dataRepresentation().flatMap { PDFDocument(data: $0) } : nil
        guard let source = original.pageRef ?? serialized?.page(at: 0)?.pageRef else { throw ocrError("Could not read the original page.") }
        let data = try OCRTextLayer.render(source: source, mediaBox: original.bounds(for: .mediaBox),
                                           cropBox: original.bounds(for: .cropBox), rotation: original.rotation, lines: lines, replacingTextWith: image)
        guard let pdf = PDFDocument(data: data), let result = pdf.page(at: 0)?.copy() as? PDFPage else {
            throw ocrError("Could not load the recognized page.")
        }
        for box in [PDFDisplayBox.mediaBox, .cropBox, .bleedBox, .trimBox, .artBox] {
            result.setBounds(original.bounds(for: box), for: box)
        }
        result.rotation = original.rotation
        for annotation in original.annotations {
            guard let copy = annotation.copy() as? PDFAnnotation else { throw ocrError("Could not preserve a page annotation.") }
            result.addAnnotation(copy)
        }
        guard result.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ocrError("No selectable text could be generated for this page.")
        }
        return result
    }

    private static func ocrError(_ message: String) -> NSError {
        NSError(domain: "PDFNano", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
