import AppKit
import ZonesCore

/// A connected display, with rects in global top-left-origin coordinates
/// (the space the Accessibility API and `ZoneGeometry` use).
struct DisplayScreen: Identifiable {
    /// Stable across reboots and reconnection: the display's UUID.
    let id: String
    let name: String
    let frame: CGRect
    /// Excludes the menu bar and Dock.
    let visibleFrame: CGRect
    let nsScreen: NSScreen

    var orientation: ScreenOrientation {
        ScreenOrientation(width: frame.width, height: frame.height)
    }

    /// Human-readable label that distinguishes identical monitor models.
    var label: String {
        let shape = orientation == .portrait ? "portrait" : "landscape"
        return "\(name) (\(Int(frame.width))×\(Int(frame.height)), \(shape))"
    }

    init(_ screen: NSScreen) {
        nsScreen = screen
        name = screen.localizedName
        frame = ScreenCoordinates.flip(screen.frame)
        visibleFrame = ScreenCoordinates.flip(screen.visibleFrame)
        id = Self.stableID(for: screen)
    }

    static var all: [DisplayScreen] { NSScreen.screens.map(DisplayScreen.init) }

    static func containing(_ point: CGPoint) -> DisplayScreen? {
        let screens = all
        return screens.first { $0.frame.contains(point) }
            ?? screens.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    /// Converts a rect in this screen's global top-left space into coordinates
    /// local to a view covering the whole screen.
    func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    private static func stableID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return screen.localizedName
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

/// Converts between AppKit's bottom-left-origin global space and the
/// top-left-origin space used by Quartz and Accessibility. Both are anchored
/// to the primary (menu bar) screen; the conversion is its own inverse.
enum ScreenCoordinates {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Current cursor position in top-left space.
    static var mouseLocation: CGPoint { flip(NSEvent.mouseLocation) }
}
