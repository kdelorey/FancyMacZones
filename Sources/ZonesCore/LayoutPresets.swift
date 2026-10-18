import Foundation

/// Starting layouts offered in the editor and installed on first launch.
public enum LayoutPresets {
    public struct Preset: Identifiable, Sendable {
        public let name: String
        public let make: @Sendable () -> LayoutNode
        public var id: String { name }
    }

    public static let all: [Preset] = [
        Preset(name: "Two Columns") { .even(.horizontal, 2) },
        Preset(name: "Three Columns") { .even(.horizontal, 3) },
        Preset(name: "Four Columns") { .even(.horizontal, 4) },
        Preset(name: "Priority Columns") { .split(.horizontal, [.zone(), .zone(), .zone()], fractions: [0.25, 0.5, 0.25]) },
        Preset(name: "Focus + Stack") { .split(.horizontal, [.zone(), .even(.vertical, 2)], fractions: [0.62, 0.38]) },
        Preset(name: "Grid 2×2") { .split(.vertical, [.even(.horizontal, 2), .even(.horizontal, 2)]) },
        Preset(name: "Grid 3×2") { .split(.vertical, [.even(.horizontal, 3), .even(.horizontal, 3)]) },
        Preset(name: "Two Rows") { .even(.vertical, 2) },
        Preset(name: "Three Rows") { .even(.vertical, 3) },
        Preset(name: "Portrait Focus") { .split(.vertical, [.zone(), .even(.horizontal, 2)], fractions: [0.6, 0.4]) },
        Preset(name: "Single Zone") { .zone() },
    ]

    public static func layout(named name: String) -> ZoneLayout? {
        all.first { $0.name == name }.map { ZoneLayout(name: $0.name, root: $0.make()) }
    }

    /// Installed on first launch: the first landscape layout is the landscape
    /// default, the first portrait (rows) layout is the portrait default.
    public static var defaults: [ZoneLayout] {
        ["Three Columns", "Three Rows", "Priority Columns", "Focus + Stack", "Grid 2×2", "Portrait Focus"]
            .compactMap(layout(named:))
    }
}
