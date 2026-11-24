import Foundation

// Compact hierarchy cues with a bounded gutter, including malformed/deep PDFs.
enum OutlineLayout {
    static func indentation(level: Int, width: CGFloat) -> CGFloat {
        min(CGFloat(max(0, level)) * 12, min(36, max(0, width * 0.20)))
    }
    static func titleX(level: Int, width: CGFloat) -> CGFloat { 22 + indentation(level: level, width: width) }
    static func disclosureX(level: Int, width: CGFloat) -> CGFloat { 6 + indentation(level: level, width: width) }
    static func titleWidth(level: Int, width: CGFloat) -> CGFloat { max(24, width - titleX(level: level, width: width) - 12) }
}
