import AppKit
import SwiftUI
import ZonesCore

/// `FancyMacZones --snapshot <dir>` renders the overlay, the editor canvas for every
/// default layout (landscape and portrait), and the editor and settings
/// windows to PNGs, then quits. Uses an in-memory config. For checking UI
/// changes without granting Accessibility or touching real windows.
@MainActor
enum DebugSnapshots {
    static let landscape = CGSize(width: 1512, height: 945)
    static let portrait = CGSize(width: 1080, height: 1895)

    static func run(_ delegate: AppDelegate, into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = delegate.store.config

        for (name, size) in [("landscape", landscape), ("portrait", portrait)] {
            let orientation = ScreenOrientation(width: size.width, height: size.height)
            let layout = config.layout(forScreen: "snapshot-\(name)", orientation: orientation)
            let zones = ZoneGeometry.zones(layout.root, in: CGRect(origin: .zero, size: size), gaps: config.gaps)
            let model = OverlayModel()
            model.zones = zones
            // Cursor in the first gap, so the snapshot shows spanning.
            if zones.count > 1 {
                let gap = CGPoint(x: (zones[0].rect.maxX + zones[1].rect.minX) / 2,
                                  y: (zones[0].rect.maxY + zones[1].rect.minY) / 2)
                let probe = zones[0].rect.maxX < zones[1].rect.minX ? CGPoint(x: gap.x, y: zones[0].rect.midY)
                                                                    : CGPoint(x: zones[0].rect.midX, y: gap.y)
                model.highlighted = ZoneGeometry.target(at: probe, in: zones, spanDistance: config.effectiveSpanDistance)?.zoneIDs ?? []
            }
            let overlay = ZoneOverlayView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
            write(overlay, to: directory.appendingPathComponent("overlay-\(name).png"))

            for layout in config.layouts {
                let canvas = LayoutCanvas(
                    root: .constant(layout.root), gaps: config.gaps, screenSize: size,
                    selectedZoneID: .constant(layout.root.zoneIDs.first))
                    .frame(width: size.width / 2, height: size.height / 2)
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor))
                let slug = layout.name.lowercased().replacingOccurrences(of: " ", with: "-")
                write(canvas, to: directory.appendingPathComponent("canvas-\(name)-\(slug).png"))
            }
        }

        delegate.openEditor()
        delegate.openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for id in ["editor", "settings"] {
                if let view = delegate.windows.window(id: id)?.contentView {
                    capture(view, to: directory.appendingPathComponent("window-\(id).png"))
                }
            }
            print("Snapshots written to \(directory.path)")
            NSApp.terminate(nil)
        }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("Failed to render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }

    private static func capture(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
