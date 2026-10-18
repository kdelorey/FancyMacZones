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
/// release, moves the window into the highlighted zone. Dragging a snapped
/// window back out restores the size it had before it was snapped.
///
/// macOS has no "window drag began" event, so a drag counts as a window move
/// once the window under the cursor at drag start has changed position.
@MainActor
final class DragSnapController {
    private let store: ConfigStore
    private let overlay: OverlayController
    private let animator = WindowAnimator()
    private var memory = SnapMemory()
    private var monitors: [Any] = []
    private var drag: DragState?

    private struct DragState {
        /// Nil when no movable window was under the cursor; the drag is ignored.
        var window: AXWindow?
        var startOrigin: CGPoint?
        var startSize: CGSize?
        var isMovingWindow = false
        /// The window's size before it was first snapped, remembered again if
        /// this drag snaps it.
        var preSnapSize: CGSize?
        /// Set when this drag pulled the window out of a zone.
        var restore: Restore?
        var target: ZoneFrame?
    }

    /// Where the cursor grabbed the window when it left its zone, so the
    /// restored window can be kept at the same spot under the cursor.
    private struct Restore {
        let size: CGSize
        /// Grab point as a fraction of the window's width.
        let grabFraction: CGFloat
        /// Grab point's distance below the window's top edge.
        let grabOffsetY: CGFloat

        /// The origin that puts a window of `size` under the current cursor.
        func origin(for size: CGSize) -> CGPoint {
            let cursor = ScreenCoordinates.mouseLocation
            return CGPoint(x: (cursor.x - grabFraction * size.width).rounded(),
                           y: (cursor.y - grabOffsetY).rounded())
        }
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
            // First drag event: remember which window is under the cursor and its frame.
            let window = AXWindow.under(ScreenCoordinates.mouseLocation)
            if let window { animator.cancel(window) }
            drag = DragState(window: window, startOrigin: window?.position, startSize: window?.size)
            return
        }
        guard var state = drag, let window = state.window else { return }
        if !state.isMovingWindow {
            guard let start = state.startOrigin, let now = window.position,
                  hypot(now.x - start.x, now.y - start.y) >= 1 else { return }
            state.isMovingWindow = true
            state.restore = leaveZone(window, at: now)
            state.preSnapSize = state.restore?.size ?? state.startSize
            drag = state
        }
        updateSnapTarget()
    }

    /// If `window` is still the size MacZones snapped it to, starts restoring
    /// its pre-snap size (when enabled) and returns how to place it.
    private func leaveZone(_ window: AXWindow, at origin: CGPoint) -> Restore? {
        guard let entry = memory.take(window), let size = window.size, entry.matches(size) else { return nil }
        let cursor = ScreenCoordinates.mouseLocation
        let restore = Restore(
            size: entry.originalSize,
            grabFraction: size.width > 0 ? min(max((cursor.x - origin.x) / size.width, 0), 1) : 0.5,
            grabOffsetY: max(cursor.y - origin.y, 0))
        guard store.config.restoreSizeOnUnsnap else {
            // Still carried so a later snap remembers the true original size.
            return Restore(size: entry.originalSize, grabFraction: 0, grabOffsetY: 0)
        }

        if store.config.animateSnapping {
            animator.animateResize(window, from: size, to: restore.size,
                                   duration: store.config.animationDuration, origin: restore.origin(for:))
        } else {
            let resume = window.suspendEnhancedUserInterface()
            window.setSize(restore.size)
            window.setPosition(restore.origin(for: restore.size))
            resume()
        }
        return restore
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
        guard let state = drag, state.isMovingWindow, let window = state.window else { return }
        if modifierHeld, let target = state.target {
            snap(window, to: target.rect, preSnapSize: state.preSnapSize)
        } else if let restore = state.restore, store.config.restoreSizeOnUnsnap {
            finishRestore(window, restore)
        }
    }

    /// Some apps (Ghostty, for one) override resizes made while they are being
    /// dragged, so the restored size is applied again once the drag ends.
    private func finishRestore(_ window: AXWindow, _ restore: Restore) {
        animator.cancel(window)
        let target = CGRect(origin: restore.origin(for: restore.size), size: restore.size)
        let apply = {
            guard let size = window.size,
                  abs(size.width - target.width) > 2 || abs(size.height - target.height) > 2 else { return }
            window.setFrame(target)
        }
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { apply() }
    }

    private func snap(_ window: AXWindow, to rect: CGRect, preSnapSize: CGSize?) {
        let settle = { [weak self] in
            // Some apps re-apply their drag position just after mouse-up; correct it
            // once they settle, then record the size they actually took.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                if let origin = window.position, origin != rect.origin {
                    window.setFrame(rect)
                }
                if let preSnapSize, let snapped = window.size {
                    self?.memory.remember(window, originalSize: preSnapSize, snappedSize: snapped)
                }
            }
        }
        if store.config.animateSnapping {
            animator.animate(window, to: rect, duration: store.config.animationDuration, completion: settle)
        } else {
            window.setFrame(rect)
            settle()
        }
    }

    private func cancel() {
        drag = nil
        overlay.hide()
    }
}

/// Sizes windows had before they were snapped, so dragging them out of a zone
/// can put them back.
struct SnapMemory {
    struct Entry {
        let window: AXWindow
        let originalSize: CGSize
        let snappedSize: CGSize

        /// Whether the window still has its snapped size, i.e. the user hasn't
        /// resized it since. Allows for apps that round their size.
        func matches(_ size: CGSize) -> Bool {
            abs(size.width - snappedSize.width) <= 2 && abs(size.height - snappedSize.height) <= 2
        }
    }

    private var entries: [Entry] = []
    private let capacity = 128

    mutating func remember(_ window: AXWindow, originalSize: CGSize, snappedSize: CGSize) {
        entries.removeAll { $0.window.isSame(window) }
        entries.append(Entry(window: window, originalSize: originalSize, snappedSize: snappedSize))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// Removes and returns the entry for `window`.
    mutating func take(_ window: AXWindow) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.window.isSame(window) }) else { return nil }
        return entries.remove(at: index)
    }
}
