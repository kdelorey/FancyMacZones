import Combine
import ServiceManagement
import SwiftUI
import ZonesCore

struct SettingsView: View {
    @Bindable var store: ConfigStore

    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Snapping") {
                Picker("Hold while dragging", selection: $store.config.snapModifier) {
                    ForEach(SnapModifier.allCases, id: \.self) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                Toggle("Show zone numbers", isOn: $store.config.showZoneNumbers)
                Toggle("Restore size when dragged out of a zone", isOn: $store.config.restoreSizeOnUnsnap)
                Toggle("Animate windows into zones", isOn: $store.config.animateSnapping)
                if store.config.animateSnapping {
                    LabeledContent("Animation length") {
                        HStack {
                            Slider(value: $store.config.animationDuration, in: AppConfig.animationDurationRange, step: 0.05)
                                .frame(width: 140)
                            Text("\(Int((store.config.animationDuration * 1000).rounded())) ms")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Gaps") {
                GapControls(gaps: $store.config.gaps)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Accessibility") {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { AccessibilityPermission.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in accessibilityGranted = AccessibilityPermission.isGranted }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
