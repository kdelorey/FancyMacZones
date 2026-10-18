import CoreGraphics
import Foundation

/// Spacing around and between zones, in points.
public struct GapSettings: Codable, Equatable, Sendable {
    /// Space between the screen edge and the outermost zones.
    public var outer: Double
    /// Space between neighbouring zones.
    public var inner: Double

    public init(outer: Double = 8, inner: Double = 8) {
        self.outer = outer
        self.inner = inner
    }

    public static let range: ClosedRange<Double> = 0...64
}

/// A zone resolved to a rectangle.
public struct ZoneFrame: Equatable, Identifiable, Sendable {
    public let id: UUID
    /// 1-based zone number, in the tree's depth-first order.
    public let number: Int
    public let rect: CGRect

    public init(id: UUID, number: Int, rect: CGRect) {
        self.id = id
        self.number = number
        self.rect = rect
    }
}

/// The draggable boundary between two children of a split.
public struct DividerFrame: Equatable, Identifiable, Sendable {
    public let splitID: UUID
    /// The divider sits between child `index` and child `index + 1`.
    public let index: Int
    public let axis: SplitAxis
    /// The gap area between the two children (zero-width when the gap is 0).
    public let rect: CGRect
    /// The area of the whole split, after outer insets.
    public let splitRect: CGRect
    public let childCount: Int
    public let gap: Double

    public var id: String { "\(splitID)-\(index)" }

    /// Converts a coordinate along the split's axis to the cumulative share
    /// that `LayoutNode.moveDivider` expects, accounting for gaps.
    public func fraction(forPosition position: CGFloat) -> Double {
        let start = axis == .horizontal ? splitRect.minX : splitRect.minY
        let length = axis == .horizontal ? splitRect.width : splitRect.height
        let usable = Double(length) - gap * Double(childCount - 1)
        guard usable > 0 else { return 0 }
        let offset = Double(position - start) - gap * Double(index) - gap / 2
        return offset / usable
    }
}

/// Resolves layout trees to rectangles.
///
/// Rects use a top-left origin with y growing downward (the Quartz / Accessibility
/// convention), so rows in a vertical split are ordered top to bottom.
public enum ZoneGeometry {
    public struct Result: Equatable, Sendable {
        public var zones: [ZoneFrame]
        public var dividers: [DividerFrame]
    }

    public static func resolve(_ root: LayoutNode, in bounds: CGRect, gaps: GapSettings) -> Result {
        var result = Result(zones: [], dividers: [])
        let outer = CGFloat(max(gaps.outer, 0))
        let dx = min(outer, bounds.width / 2)
        let dy = min(outer, bounds.height / 2)
        let area = bounds.insetBy(dx: dx, dy: dy)
        place(root, in: area, gap: max(gaps.inner, 0), into: &result)
        return result
    }

    public static func zones(_ root: LayoutNode, in bounds: CGRect, gaps: GapSettings) -> [ZoneFrame] {
        resolve(root, in: bounds, gaps: gaps).zones
    }

    private static func place(_ node: LayoutNode, in rect: CGRect, gap: Double, into result: inout Result) {
        if node.isZone {
            result.zones.append(ZoneFrame(id: node.id, number: result.zones.count + 1, rect: rect))
            return
        }
        let count = node.children.count
        let horizontal = node.axis == .horizontal
        let origin = Double(horizontal ? rect.minX : rect.minY)
        let length = Double(horizontal ? rect.width : rect.height)
        let effectiveGap = min(gap, length / Double(max(count - 1, 1)))
        let usable = max(length - effectiveGap * Double(count - 1), 0)

        // Round each edge (not each length) so gaps stay even and zones tile exactly.
        var cumulative = 0.0
        var edges: [(start: Double, end: Double)] = []
        for (index, share) in node.fractions.enumerated() {
            let offset = effectiveGap * Double(index)
            let start = (origin + cumulative * usable + offset).rounded()
            cumulative += share
            let end = (origin + cumulative * usable + offset).rounded()
            edges.append((start, end))
        }

        for (index, child) in node.children.enumerated() {
            let edge = edges[index]
            let childRect = horizontal
                ? CGRect(x: edge.start, y: rect.minY, width: edge.end - edge.start, height: rect.height)
                : CGRect(x: rect.minX, y: edge.start, width: rect.width, height: edge.end - edge.start)
            place(child, in: childRect, gap: gap, into: &result)

            if index + 1 < count {
                let next = edges[index + 1].start
                let dividerRect = horizontal
                    ? CGRect(x: edge.end, y: rect.minY, width: next - edge.end, height: rect.height)
                    : CGRect(x: rect.minX, y: edge.end, width: rect.width, height: next - edge.end)
                result.dividers.append(DividerFrame(
                    splitID: node.id, index: index, axis: node.axis, rect: dividerRect,
                    splitRect: rect, childCount: count, gap: effectiveGap))
            }
        }
    }

    /// The zone to snap to for a cursor at `point`: the zone containing it, or
    /// the nearest one when the cursor is in a gap or margin.
    public static func zone(at point: CGPoint, in zones: [ZoneFrame]) -> ZoneFrame? {
        if let hit = zones.first(where: { $0.rect.contains(point) }) { return hit }
        return zones.min { distance(point, $0.rect) < distance(point, $1.rect) }
    }

    static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
