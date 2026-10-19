import SwiftUI
import ZonesCore

/// The zone editor window: a list of layouts, a to-scale canvas for the
/// selected one, per-display assignment, and gap controls.
struct EditorView: View {
    @Bindable var store: ConfigStore
    /// Flashes zones on a real screen so gap changes can be judged in place.
    var previewOnScreen: (DisplayScreen, [ZoneFrame]) -> Void = { _, _ in }

    @State private var screens: [DisplayScreen] = DisplayScreen.all
    @State private var previewScreenID: String?
    @State private var selectedLayoutID: UUID?
    @State private var selectedZoneID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            if let layout = selectedLayout {
                detail(for: layout)
            } else {
                ContentUnavailableView("No Layout Selected", systemImage: "rectangle.split.3x1",
                                       description: Text("Pick a layout on the left, or add one."))
            }
        }
        .onAppear(perform: selectInitialState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = DisplayScreen.all
            if previewScreen == nil { previewScreenID = screens.first?.id }
        }
        .onChange(of: selectedLayoutID) { selectedZoneID = nil }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedLayoutID) {
            Section("Layouts") {
                ForEach(store.config.layouts) { layout in
                    LayoutRow(layout: layout, activeOn: screensUsing(layout))
                        .tag(layout.id)
                        .contextMenu {
                            Button("Duplicate") { duplicate(layout) }
                            Button("Delete", role: .destructive) { delete(layout) }
                                .disabled(store.config.layouts.count < 2)
                        }
                }
                .onMove { store.config.layouts.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(LayoutPresets.all) { preset in
                        Button(preset.name) { add(ZoneLayout(name: preset.name, root: preset.make())) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a layout from a preset")

                Button {
                    if let layout = selectedLayout { duplicate(layout) }
                } label: { Image(systemName: "plus.square.on.square") }
                .disabled(selectedLayout == nil)
                .help("Duplicate layout")

                Button {
                    if let layout = selectedLayout { delete(layout) }
                } label: { Image(systemName: "minus") }
                .disabled(selectedLayout == nil || store.config.layouts.count < 2)
                .help("Delete layout")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: - Detail

    private func detail(for layout: ZoneLayout) -> some View {
        VStack(spacing: 0) {
            header(for: layout)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            LayoutCanvas(
                root: rootBinding(layout.id),
                gaps: store.config.gaps,
                screenSize: previewScreen?.visibleFrame.size ?? CGSize(width: 1512, height: 945),
                selectedZoneID: $selectedZoneID,
                showNumbers: store.config.showZoneNumbers,
                onAction: { perform($0, on: $1, in: layout.id) })
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Click a zone to select it. Drag the gaps between zones to resize. Right-click for more.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Divider().padding(.top, 12)

            footer(for: layout)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private func header(for layout: ZoneLayout) -> some View {
        HStack(spacing: 12) {
            TextField("Layout name", text: nameBinding(layout.id))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 160)

            Spacer()

            Picker("Display", selection: $previewScreenID) {
                ForEach(screens) { screen in
                    Text(screen.label).tag(Optional(screen.id))
                }
            }
            .fixedSize()
            .help("The display to preview and assign this layout to")

            if let screen = previewScreen {
                if store.layout(for: screen).id == layout.id {
                    Label("Active on this display", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Use on This Display") { store.assign(layout.id, to: screen) }
                }
            }
        }
    }

    private func footer(for layout: ZoneLayout) -> some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(spacing: 4) {
                let zone = selectedZoneID.flatMap { id in layout.root.contains(id) ? id : nil }
                Button { act(.split(.horizontal), zone, layout) } label: {
                    Label("Split Columns", systemImage: "rectangle.split.2x1")
                }
                Button { act(.split(.vertical), zone, layout) } label: {
                    Label("Split Rows", systemImage: "rectangle.split.1x2")
                }
                Button { act(.equalizeSiblings, zone, layout) } label: {
                    Label("Even Out", systemImage: "equal.square")
                }
                Button(role: .destructive) { act(.delete, zone, layout) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(layout.root.zoneCount < 2)
            }
            .disabled(selectedZoneID == nil)
            .labelStyle(.titleAndIcon)

            Spacer()

            GapControls(gaps: $store.config.gaps)

            Button("Preview on Screen") {
                guard let screen = previewScreen else { return }
                previewOnScreen(screen, ZoneGeometry.zones(layout.root, in: screen.visibleFrame, gaps: store.config.gaps))
            }
            .help("Briefly show these zones on the selected display")
        }
        .controlSize(.regular)
    }

    // MARK: - State

    private var selectedLayout: ZoneLayout? {
        selectedLayoutID.flatMap { id in store.config.layouts.first { $0.id == id } }
    }

    private var previewScreen: DisplayScreen? {
        screens.first { $0.id == previewScreenID } ?? screens.first
    }

    private func screensUsing(_ layout: ZoneLayout) -> [DisplayScreen] {
        screens.filter { store.layout(for: $0).id == layout.id }
    }

    private func selectInitialState() {
        screens = DisplayScreen.all
        let current = DisplayScreen.containing(ScreenCoordinates.mouseLocation) ?? screens.first
        previewScreenID = current?.id
        if selectedLayoutID == nil {
            selectedLayoutID = current.map { store.layout(for: $0).id } ?? store.config.layouts.first?.id
        }
    }

    private func rootBinding(_ id: UUID) -> Binding<LayoutNode> {
        Binding(
            get: { store.config.layouts.first { $0.id == id }?.root ?? .zone() },
            set: { newRoot in store.updateLayout(id) { $0.root = newRoot } })
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { store.config.layouts.first { $0.id == id }?.name ?? "" },
            set: { newName in store.updateLayout(id) { $0.name = newName } })
    }

    // MARK: - Actions

    private func act(_ action: ZoneAction, _ zoneID: UUID?, _ layout: ZoneLayout) {
        guard let zoneID else { return }
        perform(action, on: zoneID, in: layout.id)
    }

    private func perform(_ action: ZoneAction, on zoneID: UUID, in layoutID: UUID) {
        store.updateLayout(layoutID) { layout in
            switch action {
            case .split(let axis):
                if let created = layout.root.splitZone(zoneID, along: axis) {
                    selectedZoneID = created
                }
            case .delete:
                if layout.root.removeZone(zoneID) {
                    selectedZoneID = nil
                }
            case .equalizeSiblings:
                if let parent = layout.root.parent(of: zoneID) {
                    layout.root.equalize(split: parent.id)
                }
            }
        }
    }

    private func add(_ layout: ZoneLayout) {
        selectedLayoutID = store.addLayout(layout)
    }

    private func duplicate(_ layout: ZoneLayout) {
        add(layout.duplicated(name: "\(layout.name) Copy"))
    }

    private func delete(_ layout: ZoneLayout) {
        guard let index = store.config.layoutIndex(layout.id), store.config.removeLayout(layout.id) else { return }
        let remaining = store.config.layouts
        selectedLayoutID = remaining[min(index, remaining.count - 1)].id
    }
}

private struct LayoutRow: View {
    let layout: ZoneLayout
    let activeOn: [DisplayScreen]

    var body: some View {
        HStack(spacing: 10) {
            LayoutThumbnail(root: layout.root)
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name.isEmpty ? "Untitled" : layout.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let zones = "\(layout.root.zoneCount) zone\(layout.root.zoneCount == 1 ? "" : "s")"
        guard !activeOn.isEmpty else { return zones }
        return zones + " · " + activeOn.map(\.name).joined(separator: ", ")
    }
}

/// Outer-margin and inner-gap sliders.
struct GapControls: View {
    @Binding var gaps: GapSettings

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            row("Outer margin", value: $gaps.outer)
            row("Gap between zones", value: $gaps.inner)
        }
    }

    private func row(_ title: String, value: Binding<Double>) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Slider(value: value, in: GapSettings.range, step: 1)
                .frame(width: 140)
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
