import AppKit
import ZonesCore

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    var snapshotDirectory: URL?
    if let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count {
        snapshotDirectory = URL(fileURLWithPath: arguments[flag + 1])
    }

    if snapshotDirectory == nil {
        ConfigFile.migrate()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate(store: ConfigStore(fileURL: snapshotDirectory == nil ? ConfigFile.defaultURL : nil))
    delegate.snapshotDirectory = snapshotDirectory
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
