import CoreGraphics
import Foundation
import Testing
@testable import ZonesCore

@Suite struct GeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func threeColumnsWithGaps() {
        let zones = ZoneGeometry.zones(.even(.horizontal, 3), in: screen, gaps: GapSettings(outer: 10, inner: 20))
        #expect(zones.count == 3)
        #expect(zones[0].rect.minX == 10)
        #expect(zones[2].rect.maxX == 990)
        #expect(zones.allSatisfy { $0.rect.minY == 10 && $0.rect.maxY == 590 })
        #expect(zones[1].rect.minX - zones[0].rect.maxX == 20)
        #expect(zones[2].rect.minX - zones[1].rect.maxX == 20)
        #expect(zones.map(\.number) == [1, 2, 3])
    }

    @Test func zeroGapsTileExactly() {
        let zones = ZoneGeometry.zones(.even(.horizontal, 3), in: screen, gaps: GapSettings(outer: 0, inner: 0))
        #expect(zones[0].rect.minX == 0)
        #expect(zones[0].rect.maxX == zones[1].rect.minX)
        #expect(zones[1].rect.maxX == zones[2].rect.minX)
        #expect(zones[2].rect.maxX == 1000)
    }

    @Test func rowsRunTopToBottom() {
        let zones = ZoneGeometry.zones(.even(.vertical, 2), in: screen, gaps: GapSettings(outer: 0, inner: 0))
        #expect(zones[0].rect == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(zones[1].rect == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    @Test func respectsScreenOrigin() {
        // A portrait monitor to the left of and above the main display.
        let portrait = CGRect(x: -1080, y: -400, width: 1080, height: 1920)
        let zones = ZoneGeometry.zones(.even(.vertical, 3), in: portrait, gaps: GapSettings(outer: 0, inner: 0))
        #expect(zones[0].rect.origin == CGPoint(x: -1080, y: -400))
        #expect(zones[2].rect.maxY == 1520)
        #expect(zones.allSatisfy { $0.rect.width == 1080 })
    }

    @Test func nestedGapsAreUniform() {
        let root = LayoutNode.split(.horizontal, [.zone(), .even(.vertical, 2)])
        let zones = ZoneGeometry.zones(root, in: screen, gaps: GapSettings(outer: 8, inner: 12))
        #expect(zones[1].rect.minX - zones[0].rect.maxX == 12)
        #expect(zones[2].rect.minY - zones[1].rect.maxY == 12)
        #expect(zones[1].rect.minX == zones[2].rect.minX)
    }

    @Test func oversizedGapsDoNotProduceNegativeRects() {
        let tiny = CGRect(x: 0, y: 0, width: 40, height: 40)
        let zones = ZoneGeometry.zones(.even(.horizontal, 4), in: tiny, gaps: GapSettings(outer: 64, inner: 64))
        #expect(zones.allSatisfy { $0.rect.width >= 0 && $0.rect.height >= 0 })
    }

    @Test func hitTestPrefersContainingZoneThenNearest() {
        let zones = ZoneGeometry.zones(.even(.horizontal, 2), in: screen, gaps: GapSettings(outer: 10, inner: 40))
        #expect(ZoneGeometry.zone(at: CGPoint(x: 100, y: 100), in: zones)?.number == 1)
        #expect(ZoneGeometry.zone(at: CGPoint(x: 900, y: 100), in: zones)?.number == 2)
        // In the gap, slightly right of center.
        #expect(ZoneGeometry.zone(at: CGPoint(x: 515, y: 100), in: zones)?.number == 2)
        // In the outer margin.
        #expect(ZoneGeometry.zone(at: CGPoint(x: 2, y: 2), in: zones)?.number == 1)
    }

    @Test func spanningInGapCoversBothZones() throws {
        let zones = ZoneGeometry.zones(.even(.horizontal, 3), in: screen, gaps: GapSettings(outer: 10, inner: 10))
        let gapX = (zones[0].rect.maxX + zones[1].rect.minX) / 2
        let target = try #require(ZoneGeometry.target(at: CGPoint(x: gapX, y: 300), in: zones, spanDistance: 20))
        #expect(target.zones.map(\.number) == [1, 2])
        #expect(target.rect == zones[0].rect.union(zones[1].rect))
    }

    @Test func spanningIgnoresZoneInteriors() throws {
        let zones = ZoneGeometry.zones(.even(.horizontal, 3), in: screen, gaps: GapSettings(outer: 10, inner: 10))
        let target = try #require(ZoneGeometry.target(at: CGPoint(x: zones[1].rect.midX, y: 300), in: zones, spanDistance: 20))
        #expect(target.zones.map(\.number) == [2])
        #expect(target.rect == zones[1].rect)
    }

    @Test func spanningOffMeansSingleZone() throws {
        let zones = ZoneGeometry.zones(.even(.horizontal, 2), in: screen, gaps: GapSettings(outer: 10, inner: 10))
        let gapX = (zones[0].rect.maxX + zones[1].rect.minX) / 2
        let target = try #require(ZoneGeometry.target(at: CGPoint(x: gapX, y: 300), in: zones, spanDistance: nil))
        #expect(target.zones.count == 1)
    }

    @Test func gridCornerSpansAllFour() throws {
        let grid = LayoutNode.split(.vertical, [.even(.horizontal, 2), .even(.horizontal, 2)])
        let zones = ZoneGeometry.zones(grid, in: screen, gaps: GapSettings(outer: 0, inner: 10))
        let target = try #require(ZoneGeometry.target(at: CGPoint(x: 500, y: 300), in: zones, spanDistance: 20))
        #expect(target.zones.count == 4)
        #expect(target.rect == screen)
    }

    @Test func spanGrowsToFillRectangle() throws {
        // columns[A, rows[B, C]]: spanning A and B covers C's rows too, since A is full height.
        let root = LayoutNode.split(.horizontal, [.zone(), .even(.vertical, 2)])
        let zones = ZoneGeometry.zones(root, in: screen, gaps: GapSettings(outer: 0, inner: 10))
        let gapX = (zones[0].rect.maxX + zones[1].rect.minX) / 2
        let target = try #require(ZoneGeometry.target(at: CGPoint(x: gapX, y: 100), in: zones, spanDistance: 20))
        #expect(Set(target.zones.map(\.number)) == [1, 2, 3])
        #expect(target.rect == screen)
    }

    @Test func dividerRoundTripsThroughFraction() {
        let gaps = GapSettings(outer: 10, inner: 20)
        var root = LayoutNode.even(.horizontal, 3)
        let divider = ZoneGeometry.resolve(root, in: screen, gaps: gaps).dividers[0]
        #expect(divider.rect.width == 20)
        let center = divider.rect.midX
        #expect(abs(divider.fraction(forPosition: center) - 1.0 / 3) < 0.001)

        root.moveDivider(inSplit: root.id, index: 0, to: divider.fraction(forPosition: center + 100))
        let moved = ZoneGeometry.resolve(root, in: screen, gaps: gaps).dividers[0]
        #expect(abs(moved.rect.midX - (center + 100)) <= 1)
    }
}

@Suite struct EditingTests {
    @Test func splittingAlongSameAxisAddsSibling() throws {
        var root = LayoutNode.even(.horizontal, 2)
        let first = root.zoneIDs[0]
        let split = root.splitZone(first, along: .horizontal)
        let created = try #require(split)
        #expect(root.children.count == 3)
        #expect(root.zoneIDs == [first, created, root.zoneIDs[2]])
        #expect(root.fractions == [0.25, 0.25, 0.5])
    }

    @Test func splittingAcrossAxisNests() throws {
        var root = LayoutNode.even(.horizontal, 2)
        let second = root.zoneIDs[1]
        let split = root.splitZone(second, along: .vertical)
        try #require(split != nil)
        #expect(root.children.count == 2)
        #expect(root.children[1].axis == .vertical)
        #expect(root.children[1].children[0].id == second)
        #expect(root.zoneCount == 3)
    }

    @Test func splittingSingleZoneRoot() throws {
        var root = LayoutNode.zone()
        let original = root.id
        let split = root.splitZone(original, along: .vertical)
        try #require(split != nil)
        #expect(root.axis == .vertical)
        #expect(root.zoneIDs.first == original)
    }

    @Test func removingGivesSpaceToNeighbourAndCollapses() {
        var root = LayoutNode.split(.horizontal, [.zone(), .even(.vertical, 2)], fractions: [0.6, 0.4])
        let left = root.zoneIDs[0]
        let bottomRight = root.zoneIDs[2]
        let removed1 = root.removeZone(bottomRight)
        #expect(removed1)
        #expect(root.children.count == 2)
        #expect(root.children.allSatisfy { $0.isZone })
        #expect(root.fractions == [0.6, 0.4])

        let removed2 = root.removeZone(root.zoneIDs[1])
        #expect(removed2)
        #expect(root.isZone)
        #expect(root.id == left)
        let removed3 = root.removeZone(left)
        #expect(!removed3)
    }

    @Test func collapsingMergesSameAxisSplits() {
        // columns[ A, rows[ B, columns[C, D] ] ] — removing B leaves columns[A, C, D].
        let inner = LayoutNode.even(.horizontal, 2)
        var root = LayoutNode.split(.horizontal, [.zone(), .split(.vertical, [.zone(), inner])], fractions: [0.5, 0.5])
        let b = root.zoneIDs[1]
        let removed4 = root.removeZone(b)
        #expect(removed4)
        #expect(root.children.count == 3)
        #expect(root.children.allSatisfy { $0.isZone })
        #expect(abs(root.fractions.reduce(0, +) - 1) < 1e-9)
        #expect(root.fractions == [0.5, 0.25, 0.25])
    }

    @Test func dividerClampsToMinimum() {
        var root = LayoutNode.even(.horizontal, 2)
        root.moveDivider(inSplit: root.id, index: 0, to: -1)
        #expect(root.fractions[0] == LayoutNode.minimumFraction)
        root.moveDivider(inSplit: root.id, index: 0, to: 2)
        #expect(abs(root.fractions[1] - LayoutNode.minimumFraction) < 1e-9)
    }

    @Test func dividerOnlyAffectsAdjacentChildren() {
        var root = LayoutNode.even(.horizontal, 4)
        root.moveDivider(inSplit: root.id, index: 1, to: 0.6)
        #expect(root.fractions[0] == 0.25)
        #expect(abs(root.fractions[1] - 0.35) < 1e-9)
        #expect(abs(root.fractions[2] - 0.15) < 1e-9)
        #expect(root.fractions[3] == 0.25)
    }

    @Test func equalize() {
        var root = LayoutNode.split(.horizontal, [.zone(), .zone()], fractions: [0.9, 0.1])
        root.equalize(split: root.id)
        #expect(root.fractions == [0.5, 0.5])
    }
}

@Suite struct ConfigTests {
    @Test func roundTripsThroughJSON() throws {
        var config = AppConfig()
        config.gaps = GapSettings(outer: 4, inner: 16)
        config.snapModifier = .option
        config.restoreSizeOnUnsnap = false
        config.animateSnapping = false
        config.animationDuration = 0.35
        config.spanZones = false
        config.spanDistance = 32
        config.screenLayouts["screen-a"] = config.layouts[2].id
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"gaps":{"outer":2,"inner":3}}"#.utf8))
        #expect(decoded.gaps == GapSettings(outer: 2, inner: 3))
        #expect(!decoded.layouts.isEmpty)
        #expect(decoded.snapModifier == .shift)
        #expect(decoded.restoreSizeOnUnsnap)
        #expect(decoded.animateSnapping)
        #expect(decoded.animationDuration == 0.2)
        #expect(decoded.spanZones)
        #expect(decoded.effectiveSpanDistance == 20)
    }

    @Test func animationDurationIsClamped() throws {
        let decoded = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"animationDuration":9}"#.utf8))
        #expect(decoded.animationDuration == AppConfig.animationDurationRange.upperBound)
    }

    @Test func brokenFractionsAreRepaired() throws {
        let json = #"{"id":"6E2A0B0E-4D0A-4C56-9B8B-1F6D1F0E4B11","axis":"horizontal","fractions":[5],"children":[{"id":"6E2A0B0E-4D0A-4C56-9B8B-1F6D1F0E4B12"},{"id":"6E2A0B0E-4D0A-4C56-9B8B-1F6D1F0E4B13"}]}"#
        let node = try JSONDecoder().decode(LayoutNode.self, from: Data(json.utf8))
        #expect(node.fractions == [0.5, 0.5])
    }

    @Test func defaultLayoutFollowsOrientation() {
        let config = AppConfig()
        #expect(config.layout(forScreen: "wide", orientation: .landscape).root.axis == .horizontal)
        #expect(config.layout(forScreen: "tall", orientation: .portrait).root.axis == .vertical)
    }

    @Test func assignmentWinsOverOrientation() {
        var config = AppConfig()
        let columns = config.layouts[0]
        config.screenLayouts["tall"] = columns.id
        #expect(config.layout(forScreen: "tall", orientation: .portrait).id == columns.id)
    }

    @Test func removingLayoutClearsAssignments() {
        var config = AppConfig()
        let target = config.layouts[1].id
        config.screenLayouts["s"] = target
        let removed5 = config.removeLayout(target)
        #expect(removed5)
        #expect(config.screenLayouts["s"] == nil)
    }

    @Test func cannotRemoveLastLayout() {
        var config = AppConfig(layouts: [ZoneLayout(name: "Only", root: .zone())])
        let removed6 = config.removeLayout(config.layouts[0].id)
        #expect(!removed6)
    }

    @Test func uniqueNames() {
        let config = AppConfig(layouts: [ZoneLayout(name: "A", root: .zone()), ZoneLayout(name: "A 2", root: .zone())])
        #expect(config.uniqueLayoutName("A") == "A 3")
        #expect(config.uniqueLayoutName("B") == "B")
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        var config = AppConfig()
        config.showZoneNumbers = false
        try ConfigFile.save(config, to: url)
        #expect(ConfigFile.load(from: url) == config)
    }
}
