import AppKit
import SwiftUI
import ZonesCore

/// Zone actions the canvas can trigger; the editor decides what they do.
enum ZoneAction {
    case split(SplitAxis)
    case delete
    case equalizeSiblings
}

/// An interactive, to-scale picture of a layout on a screen. Zones are
/// selectable and the gaps between them are draggable dividers.
struct LayoutCanvas: View {
    @Binding var root: LayoutNode
    let gaps: GapSettings
    /// The usable screen area being previewed, in points.
    let screenSize: CGSize
    @Binding var selectedZoneID: UUID?
    var showNumbers = true
    var onAction: (ZoneAction, UUID) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / screenSize.width, geometry.size.height / screenSize.height)
            let canvas = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)
            let resolved = ZoneGeometry.resolve(root, in: CGRect(origin: .zero, size: screenSize), gaps: gaps)

            ZStack(alignment: .topLeading) {
                ScreenBackdrop()
                    .onTapGesture { selectedZoneID = nil }

                ForEach(resolved.zones) { zone in
                    zoneView(zone, rect: zone.rect.scaled(by: scale), canDelete: resolved.zones.count > 1)
                }

                ForEach(resolved.dividers) { divider in
                    DividerHandle(divider: divider, scale: scale) { position in
                        root.moveDivider(inSplit: divider.splitID, index: divider.index,
                                         to: divider.fraction(forPosition: position))
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .coordinateSpace(name: LayoutCanvas.space)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(screenSize.width / max(screenSize.height, 1), contentMode: .fit)
    }

    static let space = "LayoutCanvas"

    @ViewBuilder
    private func zoneView(_ zone: ZoneFrame, rect: CGRect, canDelete: Bool) -> some View {
        let isSelected = zone.id == selectedZoneID
        ZoneTile(number: zone.number, isSelected: isSelected, showNumber: showNumbers,
                 cornerRadius: 6, numberSize: max(min(rect.width, rect.height) * 0.32, 10))
            .overlay(alignment: .bottom) {
                if isSelected && rect.width >= 104 && rect.height >= 64 {
                    ZoneButtons(canDelete: canDelete) { onAction($0, zone.id) }
                        .padding(.bottom, 8)
                }
            }
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .contentShape(Rectangle())
            .onTapGesture { selectedZoneID = zone.id }
            .contextMenu {
                Button("Split into Columns") { onAction(.split(.horizontal), zone.id) }
                Button("Split into Rows") { onAction(.split(.vertical), zone.id) }
                Button("Even Out Neighbours") { onAction(.equalizeSiblings, zone.id) }
                Divider()
                Button("Delete Zone", role: .destructive) { onAction(.delete, zone.id) }
                    .disabled(!canDelete)
            }
            .position(x: rect.midX, y: rect.midY)
            .help("Zone \(zone.number): \(Int(zone.rect.width))×\(Int(zone.rect.height)) pt")
    }
}

private struct ScreenBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(nsColor: .underPageBackgroundColor), Color(nsColor: .windowBackgroundColor)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

private struct ZoneButtons: View {
    let canDelete: Bool
    let perform: (ZoneAction) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("rectangle.split.2x1", "Split into columns") { perform(.split(.horizontal)) }
            button("rectangle.split.1x2", "Split into rows") { perform(.split(.vertical)) }
            if canDelete {
                button("trash", "Delete zone") { perform(.delete) }
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// The draggable gap between two zones. Its hit area is widened so it stays
/// grabbable when the inner gap is small or zero.
private struct DividerHandle: View {
    let divider: DividerFrame
    let scale: CGFloat
    /// Called with the cursor position along the split axis, in screen points.
    let onDrag: (CGFloat) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

    private static let minimumHitThickness: CGFloat = 12

    var body: some View {
        let rect = divider.rect.scaled(by: scale)
        let horizontal = divider.axis == .horizontal
        let thickness = max(horizontal ? rect.width : rect.height, Self.minimumHitThickness)
        let length = horizontal ? rect.height : rect.width
        let active = isHovered || isDragging

        Capsule()
            .fill(Color.accentColor.opacity(active ? 0.9 : 0.0))
            .frame(width: horizontal ? 4 : min(length * 0.4, 72), height: horizontal ? min(length * 0.4, 72) : 4)
            .frame(width: horizontal ? thickness : length, height: horizontal ? length : thickness)
            .contentShape(Rectangle())
            .position(x: rect.midX, y: rect.midY)
            .onHover { inside in
                guard inside != isHovered else { return }
                isHovered = inside
                if inside {
                    (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(LayoutCanvas.space))
                    .onChanged { value in
                        isDragging = true
                        let point = horizontal ? value.location.x : value.location.y
                        onDrag(point / scale)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovered { NSCursor.pop() }
                    }
            )
            .help("Drag to resize")
    }
}

extension CGRect {
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(x: minX * factor, y: minY * factor, width: width * factor, height: height * factor)
    }
}

/// A small static picture of a layout, for lists and menus.
struct LayoutThumbnail: View {
    let root: LayoutNode
    var size = CGSize(width: 44, height: 28)

    var body: some View {
        let zones = ZoneGeometry.zones(root, in: CGRect(origin: .zero, size: size), gaps: GapSettings(outer: 2, inner: 2))
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
            ForEach(zones) { zone in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: max(zone.rect.width, 0), height: max(zone.rect.height, 0))
                    .position(x: zone.rect.midX, y: zone.rect.midY)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
