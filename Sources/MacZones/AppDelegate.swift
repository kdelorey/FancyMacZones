import AppKit
import SwiftUI
import ZonesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: ConfigStore
    private lazy var overlay = OverlayController(store: store)
    private lazy var snapper = DragSnapController(store: store, overlay: overlay)
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    let windows = WindowPresenter()
    /// When set, renders debug snapshots into this directory and quits instead of running normally.
    var snapshotDirectory: URL?

    init(store: ConfigStore) {
        self.store = store
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let snapshotDirectory {
            DebugSnapshots.run(self, into: snapshotDirectory)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        startSnappingWhenPermitted()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: - Permission

    private func startSnappingWhenPermitted() {
        if AccessibilityPermission.isGranted {
            snapper.start()
            return
        }
        AccessibilityPermission.request()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AccessibilityPermission.isGranted else { return }
                timer.invalidate()
                self?.permissionTimer = nil
                self?.snapper.start()
            }
        }
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "MacZones")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if snapper.isRunning {
            let hint = NSMenuItem(title: "Hold \(store.config.snapModifier.displayName) while dragging a window", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            menu.addItem(withTitle: "Grant Accessibility Permission…", action: #selector(grantPermission), keyEquivalent: "")
                .target = self
        }

        for screen in DisplayScreen.all {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: screen.label))
            let active = store.layout(for: screen).id
            for layout in store.config.layouts {
                let item = NSMenuItem(title: layout.name, action: #selector(chooseLayout(_:)), keyEquivalent: "")
                item.target = self
                item.state = layout.id == active ? .on : .off
                item.representedObject = LayoutChoice(screenID: screen.id, layoutID: layout.id)
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Zones…", action: #selector(openEditor), keyEquivalent: "e").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacZones", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private final class LayoutChoice: NSObject {
        let screenID: String
        let layoutID: UUID
        init(screenID: String, layoutID: UUID) {
            self.screenID = screenID
            self.layoutID = layoutID
        }
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? LayoutChoice else { return }
        store.config.screenLayouts[choice.screenID] = choice.layoutID
    }

    @objc private func grantPermission() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }

    @objc func openEditor() {
        windows.show(id: "editor", title: "MacZones Zone Editor", size: CGSize(width: 1080, height: 720), resizable: true) {
            EditorView(store: self.store) { [weak self] screen, zones in
                self?.flashZones(zones, on: screen)
            }
        }
    }

    @objc func openSettings() {
        windows.show(id: "settings", title: "MacZones Settings", size: CGSize(width: 460, height: 420), resizable: false) {
            SettingsView(store: self.store)
        }
    }

    private var flashTask: Task<Void, Never>?

    private func flashZones(_ zones: [ZoneFrame], on screen: DisplayScreen) {
        flashTask?.cancel()
        overlay.show(on: screen, zones: zones, highlighted: nil)
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.overlay.hide()
        }
    }
}

/// Opens SwiftUI windows from a menu bar app, and shows the app in the Dock
/// and app switcher only while one is open.
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, resizable: Bool, content: () -> Content) {
        let window = windows[id] ?? makeWindow(id: id, title: title, size: size, resizable: resizable, content: content())
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(id: String, title: String, size: CGSize, resizable: Bool, content: Content) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        if resizable {
            window.setContentSize(size)
            window.contentMinSize = CGSize(width: 820, height: 520)
        }
        window.setFrameAutosaveName("MacZones.\(id)")
        if window.frame.origin == .zero { window.center() }
        window.delegate = self
        windows[id] = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let othersVisible = windows.values.contains { $0 !== closing && $0.isVisible }
        if !othersVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// For debug snapshots: the window opened under `id`, if any.
    func window(id: String) -> NSWindow? { windows[id] }
}
