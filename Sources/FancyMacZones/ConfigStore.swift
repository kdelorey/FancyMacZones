import Foundation
import Observation
import ZonesCore

/// The live, observable app config. Changes are written to disk shortly after
/// they happen, so slider drags don't hammer the file.
@MainActor
@Observable
final class ConfigStore {
    var config: AppConfig {
        didSet { if config != oldValue { scheduleSave() } }
    }

    @ObservationIgnored let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// - Parameter fileURL: Where to persist; nil keeps the config in memory only.
    init(fileURL: URL? = ConfigFile.defaultURL) {
        self.fileURL = fileURL
        config = fileURL.map { ConfigFile.load(from: $0) } ?? AppConfig()
    }

    func layout(for screen: DisplayScreen) -> ZoneLayout {
        config.layout(forScreen: screen.id, orientation: screen.orientation)
    }

    func zones(for screen: DisplayScreen) -> [ZoneFrame] {
        ZoneGeometry.zones(layout(for: screen).root, in: screen.visibleFrame, gaps: config.gaps)
    }

    func assign(_ layoutID: UUID, to screen: DisplayScreen) {
        config.screenLayouts[screen.id] = layoutID
    }

    func updateLayout(_ id: UUID, _ change: (inout ZoneLayout) -> Void) {
        guard let index = config.layoutIndex(id) else { return }
        change(&config.layouts[index])
    }

    @discardableResult
    func addLayout(_ layout: ZoneLayout) -> UUID {
        var layout = layout
        layout.name = config.uniqueLayoutName(layout.name)
        config.layouts.append(layout)
        return layout.id
    }

    func flush() {
        saveTask?.cancel()
        save()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try ConfigFile.save(config, to: fileURL)
        } catch {
            NSLog("FancyMacZones: failed to save config: \(error)")
        }
    }
}
