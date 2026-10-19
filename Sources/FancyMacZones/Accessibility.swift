import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Another application's window, driven through the Accessibility API.
/// Positions are in global top-left-origin coordinates.
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }()

    /// The top-level window under `point`, if it belongs to another app.
    static func under(_ point: CGPoint) -> AXWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit else { return nil }

        for _ in 0..<32 {
            if current.string(kAXRoleAttribute) == kAXWindowRole as String {
                return AXWindow(element: current)
            }
            if let window: AXUIElement = current.attribute(kAXWindowAttribute) {
                return AXWindow(element: window)
            }
            guard let parent: AXUIElement = current.attribute(kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    private init?(element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != getpid() else { return nil }
        self.element = element
        self.pid = pid
    }

    var position: CGPoint? {
        var point = CGPoint.zero
        return element.axValue(kAXPositionAttribute, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        var size = CGSize.zero
        return element.axValue(kAXSizeAttribute, .cgSize, &size) ? size : nil
    }

    func isSame(_ other: AXWindow) -> Bool {
        CFEqual(element, other.element)
    }

    /// Moves and resizes the window to `rect`.
    ///
    /// Position is set before and after size: moving first lets the window
    /// grow into the target screen, and the second move corrects apps that
    /// shift themselves when resized or that clamp size on the old screen.
    func setFrame(_ rect: CGRect) {
        let resume = suspendEnhancedUserInterface()
        setPosition(rect.origin)
        setSize(rect.size)
        setPosition(rect.origin)
        resume()
    }

    /// One intermediate frame of an animation: a single move and resize, with
    /// none of `setFrame`'s corrections. Call inside `suspendEnhancedUserInterface`.
    func setAnimationFrame(_ rect: CGRect) {
        setPosition(rect.origin)
        setSize(rect.size)
    }

    func setSize(_ size: CGSize) {
        var value = size
        if let axValue = AXValueCreate(.cgSize, &value) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
        }
    }

    func setPosition(_ point: CGPoint) {
        var value = point
        if let axValue = AXValueCreate(.cgPoint, &value) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
        }
    }

    /// Chromium and Electron apps animate frame changes themselves while
    /// AXEnhancedUserInterface is on, which makes the size step land wrong.
    /// Turns it off if needed and returns a closure that turns it back on.
    func suspendEnhancedUserInterface() -> () -> Void {
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        var current: CFTypeRef?
        let wasEnabled = AXUIElementCopyAttributeValue(app, attribute, &current) == .success
            && (current as? Bool) == true
        guard wasEnabled else { return {} }
        AXUIElementSetAttributeValue(app, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) }
    }
}

private extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func string(_ name: String) -> String? { attribute(name) }

    /// Reads an AXValue attribute into `result`, which must match `type`.
    func axValue(_ name: String, _ type: AXValueType, _ result: UnsafeMutableRawPointer) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return false }
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, type, result)
    }
}
