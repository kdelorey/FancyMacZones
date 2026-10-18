import AppKit
import ZonesCore

extension SnapModifier {
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .command: .command
        }
    }
}

/// Watches global mouse events. When the user drags a window while holding the
/// snap modifier, shows the zones of the screen under the cursor and, on
/// release, moves the window into the highlighted zone.
///
/// macOS has no "window drag began" event, so a drag counts as a window move
/// once the window under the cursor at drag start has changed position.
@MainActor
final class DragSnapController {
    private let store: ConfigStore
    private let overlay: OverlayController
    private var monitors: [Any] = []
    private var drag: DragState?

    private struct DragState {
        /// Nil when no movable window was under the cursor; the drag is ignored.
        var window: AXWindow?
        var startOrigin: CGPoint?
        var isMovingWindow = false
        var target: ZoneFrame?
    }

    init(store: ConfigStore, overlay: OverlayController) {
        self.store = store
        self.overlay = overlay
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancel()
    }

    private var modifierHeld: Bool {
        NSEvent.modifierFlags.contains(store.config.snapModifier.flag)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            cancel()
        case .leftMouseDragged:
            dragged()
        case .flagsChanged:
            if drag?.isMovingWindow == true { updateSnapTarget() }
        case .leftMouseUp:
            released()
        default:
            break
        }
    }

    private func dragged() {
        if drag == nil {
            // First drag event: remember which window is under the cursor and where it is.
            let window = AXWindow.under(ScreenCoordinates.mouseLocation)
            drag = DragState(window: window, startOrigin: window?.position)
            return
        }
        guard var state = drag, let window = state.window else { return }
        if !state.isMovingWindow {
            guard let start = state.startOrigin, let now = window.position,
                  hypot(now.x - start.x, now.y - start.y) >= 1 else { return }
            state.isMovingWindow = true
            drag = state
        }
        updateSnapTarget()
    }

    private func updateSnapTarget() {
        guard drag != nil else { return }
        guard modifierHeld else {
            drag?.target = nil
            overlay.hide()
            return
        }
        let cursor = ScreenCoordinates.mouseLocation
        guard let screen = DisplayScreen.containing(cursor) else { return }
        let zones = store.zones(for: screen)
        let target = ZoneGeometry.zone(at: cursor, in: zones)
        drag?.target = target
        overlay.show(on: screen, zones: zones, highlighted: target?.id)
    }

    private func released() {
        defer { cancel() }
        guard let state = drag, state.isMovingWindow, modifierHeld,
              let window = state.window, let target = state.target else { return }
        window.setFrame(target.rect)
        // Some apps re-apply their drag position just after mouse-up; set it again once they settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if let origin = window.position, origin != target.rect.origin {
                window.setFrame(target.rect)
            }
        }
    }

    private func cancel() {
        drag = nil
        overlay.hide()
    }
}
