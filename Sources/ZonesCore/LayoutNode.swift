import Foundation

/// Direction a split lays out its children.
public enum SplitAxis: String, Codable, Sendable, CaseIterable {
    /// Children side by side, left to right (columns).
    case horizontal
    /// Children stacked, top to bottom (rows).
    case vertical

    public var other: SplitAxis { self == .horizontal ? .vertical : .horizontal }
}

/// A node in a zone layout tree.
///
/// A node with no children is a zone. A node with children is a split that
/// divides its area along `axis`, giving child `i` the share `fractions[i]`.
/// `axis` is ignored on zones.
public struct LayoutNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var axis: SplitAxis
    public var children: [LayoutNode]
    public var fractions: [Double]

    public init(id: UUID = UUID(), axis: SplitAxis = .horizontal, children: [LayoutNode] = [], fractions: [Double] = []) {
        self.id = id
        self.axis = axis
        self.children = children
        self.fractions = fractions
        normalizeFractions()
    }

    public static func zone(id: UUID = UUID()) -> LayoutNode {
        LayoutNode(id: id)
    }

    /// A split with equal shares unless `fractions` is given.
    public static func split(_ axis: SplitAxis, _ children: [LayoutNode], fractions: [Double]? = nil) -> LayoutNode {
        LayoutNode(axis: axis, children: children, fractions: fractions ?? [])
    }

    /// `count` equal zones along `axis`.
    public static func even(_ axis: SplitAxis, _ count: Int) -> LayoutNode {
        .split(axis, (0..<max(count, 1)).map { _ in .zone() })
    }

    public var isZone: Bool { children.isEmpty }

    /// Zone ids in depth-first order. A zone's position here is its number.
    public var zoneIDs: [UUID] {
        isZone ? [id] : children.flatMap(\.zoneIDs)
    }

    public var zoneCount: Int { zoneIDs.count }

    public func node(withID target: UUID) -> LayoutNode? {
        if id == target { return self }
        for child in children {
            if let found = child.node(withID: target) { return found }
        }
        return nil
    }

    public func contains(_ target: UUID) -> Bool { node(withID: target) != nil }

    // MARK: - Editing

    /// Minimum share a child may be resized down to.
    public static let minimumFraction = 0.05

    /// Splits zone `zoneID` in two along `axis`. The original zone keeps its id
    /// and the first half; the new zone takes the second half.
    ///
    /// - Returns: The new zone's id, or nil if `zoneID` is not a zone in this tree.
    @discardableResult
    public mutating func splitZone(_ zoneID: UUID, along axis: SplitAxis) -> UUID? {
        let newZone = LayoutNode.zone()
        if isZone {
            guard id == zoneID else { return nil }
            self = .split(axis, [self, newZone])
            return newZone.id
        }
        for index in children.indices {
            let child = children[index]
            if child.isZone && child.id == zoneID {
                if self.axis == axis {
                    let half = fractions[index] / 2
                    fractions[index] = half
                    fractions.insert(half, at: index + 1)
                    children.insert(newZone, at: index + 1)
                } else {
                    children[index] = .split(axis, [child, newZone])
                }
                return newZone.id
            }
            if let created = children[index].splitZone(zoneID, along: axis) {
                return created
            }
        }
        return nil
    }

    /// Removes zone `zoneID`, giving its space to its neighbour. Splits left
    /// with one child collapse into that child. The last zone cannot be removed.
    ///
    /// - Returns: Whether a zone was removed.
    @discardableResult
    public mutating func removeZone(_ zoneID: UUID) -> Bool {
        guard zoneCount > 1, !isZone else { return false }
        guard removeDescendantZone(zoneID) else { return false }
        collapseSingleChildSplits()
        return true
    }

    private mutating func removeDescendantZone(_ zoneID: UUID) -> Bool {
        if let index = children.firstIndex(where: { $0.isZone && $0.id == zoneID }) {
            let freed = fractions[index]
            children.remove(at: index)
            fractions.remove(at: index)
            if !fractions.isEmpty {
                let neighbour = index > 0 ? index - 1 : 0
                fractions[neighbour] += freed
            }
            return true
        }
        for index in children.indices where !children[index].isZone {
            if children[index].removeDescendantZone(zoneID) { return true }
        }
        return false
    }

    private mutating func collapseSingleChildSplits() {
        for index in children.indices {
            children[index].collapseSingleChildSplits()
        }
        if children.count == 1 {
            self = children[0]
        } else {
            // Merge a child split that runs along the same axis into this one.
            var merged: [LayoutNode] = []
            var mergedFractions: [Double] = []
            for (child, share) in zip(children, fractions) {
                if !child.isZone && child.axis == axis {
                    merged.append(contentsOf: child.children)
                    mergedFractions.append(contentsOf: child.fractions.map { $0 * share })
                } else {
                    merged.append(child)
                    mergedFractions.append(share)
                }
            }
            children = merged
            fractions = mergedFractions
        }
    }

    /// Moves the divider between children `index` and `index + 1` of split
    /// `splitID` to `position`, a cumulative share (0...1) along the split.
    /// Only those two children change size.
    ///
    /// - Returns: Whether the split was found.
    @discardableResult
    public mutating func moveDivider(inSplit splitID: UUID, index: Int, to position: Double) -> Bool {
        if id == splitID {
            guard index >= 0, index + 1 < fractions.count else { return false }
            let start = fractions[..<index].reduce(0, +)
            let pair = fractions[index] + fractions[index + 1]
            let minimum = Swift.min(Self.minimumFraction, pair / 2)
            let first = Swift.min(Swift.max(position - start, minimum), pair - minimum)
            fractions[index] = first
            fractions[index + 1] = pair - first
            return true
        }
        for childIndex in children.indices {
            if children[childIndex].moveDivider(inSplit: splitID, index: index, to: position) { return true }
        }
        return false
    }

    /// Gives every child of split `splitID` an equal share.
    @discardableResult
    public mutating func equalize(split splitID: UUID) -> Bool {
        if id == splitID, !isZone {
            fractions = Array(repeating: 1 / Double(children.count), count: children.count)
            return true
        }
        for index in children.indices {
            if children[index].equalize(split: splitID) { return true }
        }
        return false
    }

    /// The split that directly contains `nodeID`, if any.
    public func parent(of nodeID: UUID) -> LayoutNode? {
        if children.contains(where: { $0.id == nodeID }) { return self }
        for child in children {
            if let found = child.parent(of: nodeID) { return found }
        }
        return nil
    }

    /// Makes `fractions` match `children` and sum to 1. Applied on init and decode
    /// so hand-edited config files can't produce a broken tree.
    public mutating func normalizeFractions() {
        if children.isEmpty {
            fractions = []
            return
        }
        for index in children.indices {
            children[index].normalizeFractions()
        }
        if fractions.count != children.count || fractions.contains(where: { !$0.isFinite || $0 <= 0 }) {
            fractions = Array(repeating: 1, count: children.count)
        }
        let total = fractions.reduce(0, +)
        fractions = fractions.map { $0 / total }
    }

    private enum CodingKeys: String, CodingKey {
        case id, axis, children, fractions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        axis = try container.decodeIfPresent(SplitAxis.self, forKey: .axis) ?? .horizontal
        children = try container.decodeIfPresent([LayoutNode].self, forKey: .children) ?? []
        fractions = try container.decodeIfPresent([Double].self, forKey: .fractions) ?? []
        normalizeFractions()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if !isZone {
            try container.encode(axis, forKey: .axis)
            try container.encode(children, forKey: .children)
            try container.encode(fractions, forKey: .fractions)
        }
    }
}
