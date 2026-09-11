import AppKit
import CoreGraphics

enum ScreenSnapper {
    static func builtinDisplayID() -> CGDirectDisplayID? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(displayID) != 0 {
                return displayID
            }
        }
        return nil
    }

    static func builtinScreen() -> NSScreen? {
        guard let displayID = builtinDisplayID() else { return nil }
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    static func capturePixelSize() -> (width: Int, height: Int)? {
        guard let screen = builtinScreen() else { return nil }
        let scale = screen.backingScaleFactor
        return (
            max(Int((screen.frame.width * scale).rounded()), 1),
            max(Int((screen.frame.height * scale).rounded()), 1)
        )
    }
}
