import Foundation
import IOKit.hid
import QuartzCore

/// MacBook lid-angle HID: Apple VID 0x05AC / PID 0x8104, usage 0x20/0x8A.
@MainActor
final class LidSensor {
    private(set) var angle: Double = 110
    private(set) var velocity: Double = 0
    private(set) var isAvailable = false
    private(set) var status = String(localized: "Sensor not available")

    nonisolated(unsafe) private var device: IOHIDDevice?
    nonisolated(unsafe) private var deviceOpen = false
    private var report = [UInt8](repeating: 0, count: 8)
    private var lastAngle = 0.0
    private var lastTime: TimeInterval = 0
    private var firstSample = true
    private var consecutiveFailures = 0

    nonisolated private static let options = IOOptionBits(kIOHIDOptionsTypeNone)

    init() {
        if let found = Self.findDevice() {
            device = found
            isAvailable = true
            status = String(localized: "Sensor ready")
        } else {
            status = String(localized: "Lid sensor not found")
        }
    }

    deinit {
        if deviceOpen, let device {
            IOHIDDeviceClose(device, Self.options)
        }
    }

    func start() {
        guard isAvailable, !deviceOpen, let device else { return }
        guard IOHIDDeviceOpen(device, Self.options) == kIOReturnSuccess else {
            status = String(localized: "Could not open lid sensor")
            isAvailable = false
            return
        }
        deviceOpen = true
        poll()
    }

    func poll() {
        guard deviceOpen, let device else { return }

        var length = CFIndex(report.count)
        let result = report.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            guard let base = buffer.baseAddress else { return kIOReturnNoMemory }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, base, &length)
        }
        guard result == kIOReturnSuccess, length >= 3 else {
            registerFailure()
            return
        }

        let raw = Double(UInt16(report[2]) << 8 | UInt16(report[1]))
        guard raw >= 0, raw <= 180 else {
            registerFailure()
            return
        }
        consecutiveFailures = 0

        let now = CACurrentMediaTime()

        if firstSample {
            angle = raw
            lastAngle = raw
            lastTime = now
            firstSample = false
            status = Self.label(for: raw)
            return
        }

        let changed = abs(raw - lastAngle) >= 0.5
        if changed {
            let dt = now - lastTime
            if dt > 0, dt < 0.02, abs(raw - lastAngle) > 35 {
                return
            }
            if dt > 0.018, dt < 0.5 {
                velocity = velocity * 0.38 + ((raw - lastAngle) / dt) * 0.62
            } else if dt > 0, dt < 1 {
                velocity = (raw - lastAngle) / dt
            }
            lastAngle = raw
            lastTime = now
        }

        angle = raw
        status = Self.label(for: raw)
    }

    /// Re-discovers and re-opens the HID device. The handle can go stale after
    /// the machine wakes, after which every report fails silently.
    func restart() {
        if deviceOpen, let device {
            IOHIDDeviceClose(device, Self.options)
            deviceOpen = false
        }
        firstSample = true
        lastAngle = 0
        lastTime = 0
        velocity = 0
        consecutiveFailures = 0
        if let found = Self.findDevice() {
            device = found
            isAvailable = true
            status = String(localized: "Sensor ready")
            start()
        } else {
            device = nil
            isAvailable = false
            status = String(localized: "Lid sensor not found")
        }
    }

    private func registerFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures >= 40 else { return }
        restart()
    }

    private static func label(for angle: Double) -> String {
        switch angle {
        case ..<8: String(localized: "Closed")
        case ..<40: String(localized: "Barely open")
        case ..<80: String(localized: "Halfway")
        case ..<115: String(localized: "Laptop")
        default: String(localized: "Wide open")
        }
    }

    private static func findDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        guard IOHIDManagerOpen(manager, options) == kIOReturnSuccess else { return nil }
        defer { IOHIDManagerClose(manager, options) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": 0x0020,
            "Usage": 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let cfDevices = IOHIDManagerCopyDevices(manager) else { return nil }

        let count = CFSetGetCount(cfDevices)
        var pointers = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(cfDevices, &pointers)

        var builtinMatch: IOHIDDevice?
        var otherMatch: IOHIDDevice?
        for pointer in pointers {
            guard let pointer else { continue }
            let candidate = Unmanaged<IOHIDDevice>.fromOpaque(pointer).takeUnretainedValue()
            let builtIn = (IOHIDDeviceGetProperty(candidate, "Built-In" as CFString) as? NSNumber)?.boolValue
            if builtIn == false {
                continue
            }
            guard IOHIDDeviceOpen(candidate, options) == kIOReturnSuccess else { continue }

            var probe = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(probe.count)
            let result = probe.withUnsafeMutableBufferPointer { buffer -> IOReturn in
                guard let base = buffer.baseAddress else { return kIOReturnNoMemory }
                return IOHIDDeviceGetReport(candidate, kIOHIDReportTypeFeature, 1, base, &length)
            }
            IOHIDDeviceClose(candidate, options)

            guard result == kIOReturnSuccess, length >= 3 else { continue }
            if builtIn == true {
                builtinMatch = candidate
                break
            }
            if otherMatch == nil {
                otherMatch = candidate
            }
        }
        guard let chosen = builtinMatch ?? otherMatch else { return nil }
        return Unmanaged.passRetained(chosen).takeRetainedValue()
    }
}

/// Dead band from the last accepted hinge sample.
struct LidMotionFilter {
    private(set) var angle: Double?

    mutating func reset(to sample: Double) {
        angle = sample
    }

    mutating func update(_ sample: Double, tolerance: Double) -> Double {
        guard sample.isFinite else { return angle ?? 0 }
        if angle == nil || abs(sample - angle!) > max(0, tolerance) {
            angle = sample
        }
        return angle!
    }
}
