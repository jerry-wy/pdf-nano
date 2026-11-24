import Foundation
import Vision

// Keep word positions from Vision instead of distributing an entire line in a
// substitute font. CJK graphemes are separate targets when Vision provides them.
enum OCRRecognition {
    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = [], start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index), character = text[index]
            let cjk = character.unicodeScalars.contains {
                (0x2E80...0x9FFF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
            }
            if character.isWhitespace || cjk {
                if let first = start { result.append(first..<index); start = nil }
                if cjk { result.append(index..<next) }
            } else if start == nil { start = index }
            index = next
        }
        if let start { result.append(start..<text.endIndex) }
        return result
    }
    static func line(from observation: VNRecognizedTextObservation) -> RecognizedLine? {
        guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
        let text = candidate.string, spans = ranges(in: text)
        var line = RecognizedLine(text: text, bounds: observation.boundingBox)
        var words: [RecognizedWord] = []
        for (index, span) in spans.enumerated() {
            guard let rectangle = try? candidate.boundingBox(for: span) else { return line }
            let box = rectangle.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !box.isNull, box.width > 0, box.height > 0 else { return line }
            // Some recognizers return the entire word/line for each character.
            // Fall back rather than placing several text runs on the same box.
            if let previous = words.last {
                let overlap = previous.bounds.intersection(box)
                if !overlap.isNull && overlap.width * overlap.height > 0.8 * min(previous.bounds.width * previous.bounds.height, box.width * box.height) { return line }
            }
            let end = index + 1 < spans.count ? spans[index + 1].lowerBound : text.endIndex
            words.append(RecognizedWord(text: String(text[span]), bounds: box, followingWhitespace: String(text[span.upperBound..<end])))
        }
        line.words = words
        return line
    }
}
