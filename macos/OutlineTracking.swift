import Foundation
import CoreGraphics

struct OutlinePosition: Comparable, Equatable {
    let page: Int
    let offset: CGFloat
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.page == rhs.page ? lhs.offset < rhs.offset : lhs.page < rhs.page
    }
}

struct OutlineMarker {
    let position: OutlinePosition
    let depth: Int
    let index: Int
}

// PDF destinations use unrotated page coordinates. Compare their distance from
// the displayed top, so separate sections on one page work at any zoom/rotation.
enum OutlineTracking {
    static func offset(point: CGPoint, bounds: CGRect, rotation: Int) -> CGFloat {
        let distance: CGFloat, length: CGFloat
        switch ((rotation % 360) + 360) % 360 {
        case 90: distance = point.x - bounds.minX; length = bounds.width
        case 180: distance = point.y - bounds.minY; length = bounds.height
        case 270: distance = bounds.maxX - point.x; length = bounds.width
        default: distance = bounds.maxY - point.y; length = bounds.height
        }
        guard distance.isFinite, length.isFinite, length > 0 else { return 0 }
        return min(1, max(0, distance / length))
    }
    static func sorted(_ markers: [OutlineMarker]) -> [OutlineMarker] {
        markers.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            return $0.index < $1.index
        }
    }
    // Last destination reached; ties select the most specific heading. Search
    // the cached index instead of walking the full outline on every scroll tick.
    static func active(in markers: [OutlineMarker], at position: OutlinePosition) -> Int? {
        var low = 0, high = markers.count
        while low < high {
            let mid = (low + high) / 2
            if markers[mid].position <= position { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? markers[low - 1].index : nil
    }
}
