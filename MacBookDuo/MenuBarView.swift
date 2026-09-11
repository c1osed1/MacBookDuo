import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacBook Duo")
                    .font(.headline)
                Text("Lid fold transition")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                labeled("Lid", value: String(format: "%.1f°", model.angle))
                labeled("Fold", value: String(format: "%.0f%%", model.progress * 100))
                labeled("Sensor", value: model.sensorStatus)
            }
            .font(.system(.body, design: .rounded).monospacedDigit())
            Slider(value: $model.intensity, in: 0.8...1.85) {
                Text("Depth")
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
            }
            Button("Quit MacBook Duo") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func labeled(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
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
            window.setContentSize(NSSize(width: 420, height: 520))
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
                Slider(value: $model.intensity, in: 0.8...1.85) {
                    Text("Depth")
                }
                Text("How far the glass recedes as the lid closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.openAngle, in: 50...160) {
                    Text("Start fold")
                }
                Text("Animation begins as the lid passes this angle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.closedAngle, in: 5...50) {
                    Text("Fully folded")
                }
                Text("Fully receded pose. Keep this below Start fold.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Enable lid effect", isOn: $model.enabled)
            }
            Section {
                Button("Play open / close") {
                    model.playCannedDemo()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .frame(minWidth: 380, minHeight: 480)
    }
}
