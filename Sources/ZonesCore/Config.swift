import Foundation

/// A named zone layout that can be assigned to one or more screens.
public struct ZoneLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var root: LayoutNode

    public init(id: UUID = UUID(), name: String, root: LayoutNode) {
        self.id = id
        self.name = name
        self.root = root
    }

    /// A copy with fresh ids throughout, so it can live beside the original.
    public func duplicated(name: String) -> ZoneLayout {
        ZoneLayout(name: name, root: root.withFreshIDs())
    }
}

extension LayoutNode {
    func withFreshIDs() -> LayoutNode {
        LayoutNode(axis: axis, children: children.map { $0.withFreshIDs() }, fractions: fractions)
    }
}

/// Modifier key that must be held while dragging a window to snap it.
public enum SnapModifier: String, Codable, Sendable, CaseIterable {
    case shift, option, control, command

    public var displayName: String {
        switch self {
        case .shift: "⇧ Shift"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        }
    }
}

/// Screen shape, used to pick a sensible default layout.
public enum ScreenOrientation: Sendable {
    case landscape, portrait

    public init(width: Double, height: Double) {
        self = height > width ? .portrait : .landscape
    }
}

/// Everything FancyMacZones persists.
public struct AppConfig: Codable, Equatable, Sendable {
    public var layouts: [ZoneLayout]
    /// Screen id → layout id. Screens without an entry get a default by orientation.
    public var screenLayouts: [String: UUID]
    public var gaps: GapSettings
    public var snapModifier: SnapModifier
    public var showZoneNumbers: Bool
    /// Whether a snapped window returns to its pre-snap size when dragged out of its zone.
    public var restoreSizeOnUnsnap: Bool
    /// Whether snapping glides the window into its zone instead of jumping.
    public var animateSnapping: Bool
    /// Length of the snap animation, in seconds.
    public var animationDuration: Double

    public static let animationDurationRange: ClosedRange<Double> = 0.1...0.5

    /// Whether dragging near the gap between zones spans all of them.
    public var spanZones: Bool
    /// How close, in points, the cursor must be to a zone for it to be spanned.
    public var spanDistance: Double

    public static let spanDistanceRange: ClosedRange<Double> = 4...64

    /// `spanDistance` when spanning is on, otherwise nil.
    public var effectiveSpanDistance: Double? { spanZones ? spanDistance : nil }

    public init(
        layouts: [ZoneLayout] = LayoutPresets.defaults,
        screenLayouts: [String: UUID] = [:],
        gaps: GapSettings = GapSettings(),
        snapModifier: SnapModifier = .shift,
        showZoneNumbers: Bool = true,
        restoreSizeOnUnsnap: Bool = true,
        animateSnapping: Bool = true,
        animationDuration: Double = 0.2,
        spanZones: Bool = true,
        spanDistance: Double = 20
    ) {
        self.layouts = layouts.isEmpty ? LayoutPresets.defaults : layouts
        self.screenLayouts = screenLayouts
        self.gaps = gaps
        self.snapModifier = snapModifier
        self.showZoneNumbers = showZoneNumbers
        self.restoreSizeOnUnsnap = restoreSizeOnUnsnap
        self.animateSnapping = animateSnapping
        self.animationDuration = min(max(animationDuration, Self.animationDurationRange.lowerBound),
                                     Self.animationDurationRange.upperBound)
        self.spanZones = spanZones
        self.spanDistance = min(max(spanDistance, Self.spanDistanceRange.lowerBound), Self.spanDistanceRange.upperBound)
    }

    /// The layout for a screen: its assignment if valid, otherwise the first
    /// layout whose shape suits the screen's orientation.
    public func layout(forScreen screenID: String, orientation: ScreenOrientation) -> ZoneLayout {
        if let assigned = screenLayouts[screenID], let layout = layouts.first(where: { $0.id == assigned }) {
            return layout
        }
        return layouts.first(where: { $0.root.suits(orientation) }) ?? layouts[0]
    }

    public func layoutIndex(_ id: UUID) -> Int? {
        layouts.firstIndex { $0.id == id }
    }

    /// Removes a layout and any screen assignments pointing at it. The last
    /// layout cannot be removed.
    @discardableResult
    public mutating func removeLayout(_ id: UUID) -> Bool {
        guard layouts.count > 1, let index = layoutIndex(id) else { return false }
        layouts.remove(at: index)
        screenLayouts = screenLayouts.filter { $0.value != id }
        return true
    }

    /// `base`, or `base 2`, `base 3`… whichever is not already taken.
    public func uniqueLayoutName(_ base: String) -> String {
        let names = Set(layouts.map(\.name))
        if !names.contains(base) { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    private enum CodingKeys: String, CodingKey {
        case layouts, screenLayouts, gaps, snapModifier, showZoneNumbers, restoreSizeOnUnsnap
        case animateSnapping, animationDuration, spanZones, spanDistance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppConfig()
        self.init(
            layouts: try container.decodeIfPresent([ZoneLayout].self, forKey: .layouts) ?? fallback.layouts,
            screenLayouts: try container.decodeIfPresent([String: UUID].self, forKey: .screenLayouts) ?? [:],
            gaps: try container.decodeIfPresent(GapSettings.self, forKey: .gaps) ?? fallback.gaps,
            snapModifier: try container.decodeIfPresent(SnapModifier.self, forKey: .snapModifier) ?? fallback.snapModifier,
            showZoneNumbers: try container.decodeIfPresent(Bool.self, forKey: .showZoneNumbers) ?? fallback.showZoneNumbers,
            restoreSizeOnUnsnap: try container.decodeIfPresent(Bool.self, forKey: .restoreSizeOnUnsnap)
                ?? fallback.restoreSizeOnUnsnap,
            animateSnapping: try container.decodeIfPresent(Bool.self, forKey: .animateSnapping) ?? fallback.animateSnapping,
            animationDuration: try container.decodeIfPresent(Double.self, forKey: .animationDuration)
                ?? fallback.animationDuration,
            spanZones: try container.decodeIfPresent(Bool.self, forKey: .spanZones) ?? fallback.spanZones,
            spanDistance: try container.decodeIfPresent(Double.self, forKey: .spanDistance) ?? fallback.spanDistance
        )
    }
}

extension LayoutNode {
    /// Whether the top-level split runs the way that suits a screen shape:
    /// columns for landscape, rows for portrait. A single zone suits both.
    func suits(_ orientation: ScreenOrientation) -> Bool {
        if isZone { return true }
        return axis == (orientation == .portrait ? .vertical : .horizontal)
    }
}

/// Reads and writes `AppConfig` as JSON.
public enum ConfigFile {
    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["FANCYMACZONES_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        return supportDirectory.appendingPathComponent("FancyMacZones/config.json")
    }

    /// Where the app kept its config when it was called MacZones.
    public static var legacyURL: URL {
        supportDirectory.appendingPathComponent("MacZones/config.json")
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Copies the config from `legacy` to `url` when `url` doesn't exist yet.
    /// The legacy file is left in place.
    ///
    /// - Returns: Whether a config was copied.
    @discardableResult
    public static func migrate(from legacy: URL = legacyURL, to url: URL = defaultURL) -> Bool {
        let files = FileManager.default
        guard !files.fileExists(atPath: url.path), files.fileExists(atPath: legacy.path) else { return false }
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: legacy, to: url)
            return true
        } catch {
            return false
        }
    }

    /// Loads the config, or returns defaults when the file is missing or unreadable.
    public static func load(from url: URL = defaultURL) -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public static func save(_ config: AppConfig, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
