import AppKit
import ServiceManagement
import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var selection: SidebarItem? = .general
    @State private var sidebarSearch = ""

    private var activeItem: SidebarItem { selection ?? .general }

    private var filteredSidebarItems: [SidebarItem] {
        guard !sidebarSearch.isEmpty else { return SidebarItem.allCases }
        return SidebarItem.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(sidebarSearch)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredSidebarItems, selection: $selection) { item in
                SidebarRow(item: item)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .navigationTitle(activeItem.title)
                .navigationSplitViewColumnWidth(
                    min: SettingsMetrics.detailMinWidth,
                    ideal: SettingsMetrics.detailIdealWidth
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Preview") {
                            model.playCannedDemo()
                        }
                    }
                }
        }
        .searchable(text: $sidebarSearch, placement: .sidebar, prompt: "Search")
        .background {
            SettingsWindowChrome()
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch activeItem {
        case .general: GeneralPane(model: model)
        case .look: LookPane(model: model)
        case .lid: LidPane(model: model)
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.title)
        } icon: {
            SettingsIconBadge(
                symbol: item.symbol,
                color: item.iconColor,
                size: SettingsMetrics.sidebarIconSize
            )
        }
    }
}

private enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case general
    case look
    case lid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .look: "Look"
        case .lid: "Lid"
        }
    }

    var symbol: String {
        switch self {
        case .general: "rectangle.split.2x1"
        case .look: "cube.transparent"
        case .lid: "laptopcomputer"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: SettingsPalette.gray
        case .look: SettingsPalette.blue
        case .lid: SettingsPalette.indigo
        }
    }
}

private struct GeneralPane: View {
    @Bindable var model: AppModel
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SettingsPane {
            Section {
                SettingsHeader(
                    title: "MacBook Duo",
                    subtitle: "When the lid closes, the built-in display recedes in 3D. Glass freezes one frame. Duo+ keeps the live desktop.",
                    appIcon: NSApp.applicationIconImage
                )
            }

            Section {
                Toggle("Enable lid effect", isOn: $model.enabled)
                SettingsActionRow(
                    title: "Preview on screen",
                    symbol: "play.fill",
                    color: SettingsPalette.green,
                    subtitle: "Play a canned open / close"
                ) {
                    model.playCannedDemo()
                }
            }

            Section {
                SettingsValueRow(
                    title: "Look",
                    symbol: "cube.transparent",
                    color: SettingsPalette.blue,
                    value: model.foldMode.title
                )
                SettingsValueRow(
                    title: "Lid",
                    symbol: "angle",
                    color: SettingsPalette.indigo,
                    value: String(format: "%.1f°", model.angle)
                )
                SettingsValueRow(
                    title: "Sensor",
                    symbol: "sensor.tag.radiowaves.forward",
                    color: SettingsPalette.teal,
                    value: model.sensorStatus
                )
            } header: {
                Text("Status")
            }

            if model.lastCaptureFailed {
                Section {
                    Text("Turn on Screen Recording for MacBook Duo in System Settings → Privacy & Security.")
                        .foregroundStyle(.secondary)
                    SettingsActionRow(
                        title: "Open Screen Recording settings",
                        symbol: "gear",
                        color: SettingsPalette.orange
                    ) {
                        openScreenRecordingSettings()
                    }
                } header: {
                    Text("Permission")
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                SettingsActionRow(
                    title: "Quit MacBook Duo",
                    symbol: "power",
                    color: SettingsPalette.red,
                    subtitle: "Stops capture so the recording indicator clears",
                    isDestructive: true
                ) {
                    NSApp.terminate(nil)
                }
            } header: {
                Text("App")
            } footer: {
                Text("Close this window to leave the Dock. MacBook Duo stays in the menu bar and the lid fold keeps running.")
            }
        }
        .onAppear {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct LookPane: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                Picker("Look", selection: $model.foldMode) {
                    ForEach(FoldMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(
                    model.foldMode == .glass
                        ? "Glass freezes one frame, then stops capture."
                        : "Duo+ keeps the live desktop and warps it around the hinge."
                )
                .foregroundStyle(.secondary)
            }

            if model.foldMode == .glass {
                Section {
                    Slider(value: $model.intensity, in: 0.8...1.85) {
                        Text("Depth")
                    }
                    Text("How far the glass recedes as the lid closes.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Glass")
                }
            }

            if model.foldMode == .duoPlus {
                Section {
                    Slider(value: $model.maxBlurRadius, in: 10...160) {
                        Text("Blur")
                    } minimumValueLabel: {
                        Text("10")
                    } maximumValueLabel: {
                        Text("160")
                    }
                    Text("Blur radius at the far edge.")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.blurEvenness, in: 0...1) {
                        Text("Blur spread")
                    }
                    Text("0 blurs the far edge only, 100 the whole picture.")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.maxDim, in: 0...1) {
                        Text("Dimming")
                    }
                    Slider(value: $model.dimReach, in: 0.2...1) {
                        Text("Dimming spread")
                    }
                    Slider(value: $model.recession, in: 0...3) {
                        Text("Lean back")
                    }
                    Text("1 holds the picture still in the room. Lower follows the lid.")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.perspective, in: 0...1) {
                        Text("Perspective")
                    }
                    Text("0 keeps the sides parallel, 100 converges sharply.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Duo+")
                }
            }

            Section {
                SettingsActionRow(
                    title: "Reset look",
                    symbol: "arrow.counterclockwise",
                    color: SettingsPalette.gray
                ) {
                    model.resetLook()
                }
            }
        }
    }
}

private struct LidPane: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsPane {
            Section {
                SettingsValueRow(
                    title: "Live angle",
                    symbol: "angle",
                    color: SettingsPalette.indigo,
                    value: String(format: "%.1f°", model.angle)
                )
                SettingsValueRow(
                    title: "Fold",
                    symbol: "rectangle.split.2x1",
                    color: SettingsPalette.blue,
                    value: String(format: "%.0f%%", model.progress * 100)
                )
                SettingsValueRow(
                    title: "Sensor",
                    symbol: "sensor.tag.radiowaves.forward",
                    color: SettingsPalette.teal,
                    value: model.sensorStatus
                )
            } header: {
                Text("Now")
            }

            Section {
                Slider(value: $model.openAngle, in: 50...160) {
                    Text("Start fold")
                }
                Text(String(format: "Begins at %.0f°", model.openAngle))
                    .foregroundStyle(.secondary)
                Slider(value: $model.closedAngle, in: 5...50) {
                    Text("Fully folded")
                }
                Text(String(format: "Done at %.0f°", model.closedAngle))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Range")
            }

            Section {
                Toggle("Drive the built-in display from this slider", isOn: $model.driveDisplayFromDemo)
                Slider(value: $model.demoAngle, in: 10...140) {
                    Text("Demo angle")
                }
                Text("\(Int(model.openAngle))° is a normal laptop pose. Drag toward \(Int(model.closedAngle))° to fold, or close the real lid.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Studio")
            }
        }
    }
}
