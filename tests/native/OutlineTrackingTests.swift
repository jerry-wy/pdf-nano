import Foundation
import CoreGraphics

@main struct OutlineTrackingTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: \(message)")
    }
    static func main() {
        let entries = OutlineTracking.sorted([
            OutlineMarker(position: .init(page: 3, offset: 0), depth: 0, index: 3),
            OutlineMarker(position: .init(page: 1, offset: 0.55), depth: 1, index: 2),
            OutlineMarker(position: .init(page: 1, offset: 0.1), depth: 0, index: 0),
            OutlineMarker(position: .init(page: 1, offset: 0.1), depth: 1, index: 1)
        ])
        check(OutlineTracking.active(in: entries, at: .init(page: 0, offset: 1)) == nil, "Front matter before the first heading has no misleading highlight")
        check(OutlineTracking.active(in: entries, at: .init(page: 1, offset: 0.1)) == 1, "Exact destination selects the most specific heading")
        check(OutlineTracking.active(in: entries, at: .init(page: 1, offset: 0.54)) == 1, "The next same-page section is not selected too early")
        check(OutlineTracking.active(in: entries, at: .init(page: 1, offset: 0.55)) == 2, "Scrolling within a page advances to the next section")
        check(OutlineTracking.active(in: entries, at: .init(page: 2, offset: 0.9)) == 2, "Pages between headings retain their section")
        check(OutlineTracking.active(in: entries, at: .init(page: 3, offset: 0)) == 3, "Crossing a chapter boundary changes the active heading")
        check(OutlineTracking.active(in: entries, at: .init(page: 1, offset: 0.2)) == 1, "Scrolling backward restores the previous section")
        check(OutlineTracking.active(in: [], at: .init(page: 1, offset: 0)) == nil, "PDFs without destinations are supported")
        let crop = CGRect(x: 20, y: 30, width: 400, height: 600)
        for (rotation, point) in [(0, CGPoint(x: 100, y: 480)), (90, CGPoint(x: 120, y: 100)),
                                  (180, CGPoint(x: 100, y: 180)), (270, CGPoint(x: 320, y: 100)), (-90, CGPoint(x: 320, y: 100))] {
            check(OutlineTracking.offset(point: point, bounds: crop, rotation: rotation) == 0.25,
                  "Reading position respects crop origins and rotation \(rotation)")
        }
        check(OutlineTracking.offset(point: CGPoint(x: 0, y: 900), bounds: crop, rotation: 0) == 0, "Page margins clamp to the page start")
        check(OutlineTracking.offset(point: CGPoint(x: 0, y: -90), bounds: crop, rotation: 0) == 1, "The bottom margin clamps to the page end")
    }
}
