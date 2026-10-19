import AppKit
import Observation
import SwiftUI
import ZonesCore

@MainActor
@Observable
final class OverlayModel {
    /// Zones in view-local coordinates.
    var zones: [ZoneFrame] = []
    var highlighted: Set<UUID> = []
    var showNumbers = true
}

/// Draws a screen's zones while a window is being dragged.
struct ZoneOverlayView: View {
    let model: OverlayModel

    /// The area a window will fill when it spans more than one zone.
    private var spanRect: CGRect? {
        let spanned = model.zones.filter { model.highlighted.contains($0.id) }
        guard spanned.count > 1 else { return nil }
        return SnapTarget(zones: spanned).rect
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.zones) { zone in
                ZoneTile(number: zone.number, isHighlighted: model.highlighted.contains(zone.id), showNumber: model.showNumbers)
                    .frame(width: zone.rect.width, height: zone.rect.height)
                    .offset(x: zone.rect.minX, y: zone.rect.minY)
            }
            if let span = spanRect {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .frame(width: span.width, height: span.height)
                    .offset(x: span.minX, y: span.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.08), value: model.highlighted)
    }
}

/// One zone: tinted, outlined, numbered. Shared by the overlay and the editor.
struct ZoneTile: View {
    let number: Int
    var isHighlighted = false
    var isSelected = false
    var showNumber = true
    var cornerRadius: CGFloat = 10
    var numberSize: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.accentColor.opacity(isHighlighted ? 0.45 : isSelected ? 0.3 : 0.14))
            .overlay(shape.strokeBorder(
                Color.accentColor.opacity(isHighlighted || isSelected ? 0.95 : 0.55),
                lineWidth: isHighlighted || isSelected ? 3 : 1.5))
            .overlay {
                if showNumber {
                    Text("\(number)")
                        .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isHighlighted ? 0.95 : 0.7))
                        .shadow(color: .black.opacity(0.35), radius: 3)
                        .minimumScaleFactor(0.2)
                        .padding(4)
                }
            }
    }
}

/// Owns one click-through overlay window per screen and shows the one under
/// the cursor while snapping.
@MainActor
final class OverlayController {
    private let store: ConfigStore
    private var windows: [String: (panel: NSPanel, model: OverlayModel)] = [:]
    private var visibleScreenID: String?

    init(store: ConfigStore) {
        self.store = store
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    /// Shows `screen`'s zones with `highlighted` emphasised, hiding other screens' overlays.
    func show(on screen: DisplayScreen, zones: [ZoneFrame], highlighted: Set<UUID> = []) {
        if visibleScreenID != screen.id {
            hide()
        }
        let entry = window(for: screen)
        entry.model.zones = zones.map { ZoneFrame(id: $0.id, number: $0.number, rect: screen.local($0.rect)) }
        entry.model.highlighted = highlighted
        entry.model.showNumbers = store.config.showZoneNumbers
        if visibleScreenID != screen.id {
            entry.panel.setFrame(screen.nsScreen.frame, display: true)
            entry.panel.orderFrontRegardless()
            visibleScreenID = screen.id
        }
    }

    func hide() {
        for entry in windows.values { entry.panel.orderOut(nil) }
        visibleScreenID = nil
    }

    private func rebuild() {
        hide()
        for entry in windows.values { entry.panel.close() }
        windows.removeAll()
    }

    private func window(for screen: DisplayScreen) -> (panel: NSPanel, model: OverlayModel) {
        if let existing = windows[screen.id] { return existing }
        let model = OverlayModel()
        let panel = NSPanel(
            contentRect: screen.nsScreen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ZoneOverlayView(model: model))
        windows[screen.id] = (panel, model)
        return (panel, model)
    }
}
