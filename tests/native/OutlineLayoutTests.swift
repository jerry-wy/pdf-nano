import Foundation

@main struct OutlineLayoutTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func main() {
        for width: CGFloat in [150, 180, 240, 380] {
            check(OutlineLayout.titleX(level: 0, width: width) == 22, "Root stays at left edge at width \(width)")
            check(OutlineLayout.titleX(level: 1, width: width) - OutlineLayout.titleX(level: 0, width: width) == 12,
                  "Child titles have a visible hierarchy indent at width \(width)")
            for level in 0...100 {
                let x = OutlineLayout.titleX(level: level, width: width)
                let disclosure = OutlineLayout.disclosureX(level: level, width: width)
                guard x - disclosure == 16 && x <= min(58, 22 + width * 0.2)
                      && abs(x + OutlineLayout.titleWidth(level: level, width: width) + 12 - width) < 0.01 else {
                    check(false, "Invalid layout at depth \(level), width \(width)"); return
                }
            }
            check(true, "Depths 0–100 retain readable text and disclosure spacing at \(width)")
        }
        check(OutlineLayout.titleX(level: -1, width: 200) == 22, "Unknown depth uses the root inset")
    }
}
