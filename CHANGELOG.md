# Changelog

## 1.2.3 — 2026-09-11

Do not pop the menu open on launch. After a reboot, enable MacBook Duo under System Settings → Menu Bar if the extra is missing.

## 1.2.2 — 2026-09-11

Glass now freezes a real desktop frame and keeps it after Screen Recording stops.

- Persist the freeze so Glass does not go blank when the capture stream ends
- Skip capture until ScreenCaptureKit can exclude this process (fail closed)
- Show the overlay as soon as a frame exists instead of waiting for another

## 1.2.1 — 2026-09-11

Stop Screen Recording when the lid opens again, and start the next fold instead of leaving capture running with no overlay.

## 1.2 — 2026-09-11

Duo+ keeps the live desktop and warps it around the hinge. Glass still freezes one frame.

- Duo+ look with perspective, recession, blur, and dim sliders
- Preview replays without waiting for the Screen Recording pill
- Closing the lid right after Preview follows the real hinge
- Idle CPU/GPU drop: no 120 Hz tick while the lid is just open
- Skip Studio Display HID that reads 0°; start fold only on a closing motion
- Launch at login, angle in the menu bar, and Reset look

Duo+ is adapted from [Mac Duo](https://github.com/sumimakito/Mac-Duo) by Makito (Apache-2.0).

## 1.1 — 2026-09-11

Keep the fold on the built-in display.

Configurable start/end lid angles, idle tick rate, and capture that stops after the freeze so switching screens does not hang or burn GPU.

## 1.0 — 2026-09-11

First public build.

- Menu-bar lid-fold on the built-in display
- Drag the app into Applications from the DMG
- Grant Screen Recording when asked
- Quit from the menu-bar panel so capture stops
