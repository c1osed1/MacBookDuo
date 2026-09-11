import AppKit
import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacBook Duo")
                    .font(.headline)
                Text("Lid fold transition")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Picker("Look", selection: $model.foldMode) {
                ForEach(FoldMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.foldMode == .glass
                 ? "Glass freezes one frame, then stops capture."
                 : "Duo+ keeps the live desktop and warps it around the hinge.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                labeled("Lid", value: String(format: "%.1f°", model.angle))
                labeled("Fold", value: String(format: "%.0f%%", model.progress * 100))
                labeled("Sensor", value: model.sensorStatus)
            }
            .font(.system(.body, design: .rounded).monospacedDigit())
            if model.foldMode == .glass {
                Slider(value: $model.intensity, in: 0.8...1.85) {
                    Text("Depth")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Start fold")
                    .foregroundStyle(.secondary)
                Slider(value: $model.openAngle, in: 50...160)
                Text(String(format: "Begins at %.0f°", model.openAngle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Fully folded")
                    .foregroundStyle(.secondary)
                Slider(value: $model.closedAngle, in: 5...50)
                Text(String(format: "Done at %.0f°", model.closedAngle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.foldMode == .duoPlus {
                DuoPlusLookControls(model: model)
            }
            Toggle("Enable lid effect", isOn: $model.enabled)
            HStack {
                Button("Preview on screen") {
                    model.playCannedDemo()
                }
                Button("Studio") {
                    model.openStudio()
                }
            }
            if model.lastCaptureFailed {
                Text("Turn on Screen Recording for MacBook Duo in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Screen Recording settings") {
                    openScreenRecordingSettings()
                }
                .font(.caption)
            }
            Toggle("Show angle in menu bar", isOn: $model.showsAngleInMenuBar)
            Toggle("Launch at login", isOn: $launchesAtLogin)
                .onChange(of: launchesAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            HStack {
                Button("Reset look") {
                    model.resetLook()
                }
                Spacer()
                Button("Quit MacBook Duo") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func labeled(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
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

struct DuoPlusLookControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lookSlider("Blur", value: $model.maxBlurRadius, in: 10...160, readout: String(format: "%.0f pt", model.maxBlurRadius))
            percentSlider("Blur spread", value: $model.blurEvenness)
            percentSlider("Dimming", value: $model.maxDim)
            lookSlider("Dimming spread", value: $model.dimReach, in: 0.2...1, readout: String(format: "%.0f%%", model.dimReach * 100))
            lookSlider("Lean back", value: $model.recession, in: 0...3, readout: String(format: "%.1f×", model.recession))
            percentSlider("Perspective", value: $model.perspective)
        }
    }

    private func lookSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, readout: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(readout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: range)
        }
    }

    private func percentSlider(_ title: String, value: Binding<Double>) -> some View {
        lookSlider(title, value: value, in: 0...1, readout: String(format: "%.0f%%", value.wrappedValue * 100))
    }
}

@MainActor
final class StudioWindow {
    static let shared = StudioWindow()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: StudioView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "MacBook Duo Studio"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 420, height: 640))
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        } else if let host = window?.contentViewController as? NSHostingController<StudioView> {
            host.rootView = StudioView(model: model)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct StudioView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Lid") {
                LabeledContent("Live angle", value: String(format: "%.1f°", model.sensor.angle))
                LabeledContent("Sensor", value: model.sensorStatus)
                Toggle("Drive the built-in display from this slider", isOn: $model.driveDisplayFromDemo)
                VStack(alignment: .leading) {
                    Text("Demo angle")
                    Slider(value: $model.demoAngle, in: 10...140)
                    Text("\(Int(model.openAngle))° is a normal laptop pose. Drag toward \(Int(model.closedAngle))° to fold, or close the real lid.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Look") {
                Picker("Mode", selection: $model.foldMode) {
                    ForEach(FoldMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if model.foldMode == .glass {
                    Slider(value: $model.intensity, in: 0.8...1.85) {
                        Text("Depth")
                    }
                    Text("How far the glass recedes as the lid closes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.openAngle, in: 50...160) {
                    Text("Start fold")
                }
                Slider(value: $model.closedAngle, in: 5...50) {
                    Text("Fully folded")
                }
                Toggle("Enable lid effect", isOn: $model.enabled)
            }
            if model.foldMode == .duoPlus {
                Section("Duo+") {
                    Slider(value: $model.maxBlurRadius, in: 10...160) {
                        Text("Blur")
                    }
                    Text("Blur radius at the far edge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.blurEvenness, in: 0...1) {
                        Text("Blur spread")
                    }
                    Text("0 blurs the far edge only, 100 the whole picture.")
                        .font(.caption)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $model.perspective, in: 0...1) {
                        Text("Perspective")
                    }
                    Text("0 keeps the sides parallel, 100 converges sharply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Reset look") {
                        model.resetLook()
                    }
                }
            }
            Section {
                Button("Play open / close") {
                    model.playCannedDemo()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .frame(minWidth: 380, minHeight: 560)
    }
}
