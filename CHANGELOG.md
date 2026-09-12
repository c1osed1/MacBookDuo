# Changelog

## Unreleased

## 1.5.1 — 2026-09-12

Frost keeps the far edge milky instead of punching a black hole. Blur is a continuous Gaussian, with a little hinge chroma. Opening the lid after a full close plays the fold in reverse.

## 1.5.0 — 2026-09-12

The app is Linger. Same hinge, same looks. The GitHub repo URL is unchanged.

Look is a gallery: one Mac on top, Glass / Duo+ / Frost as cards that play the full fold. Frost stretches the live plane up and milks the far edge. The hinge ignores idle jitter so Screen Recording does not blink while the lid is still.

The app and menu bar follow the system language (English or Russian).

## 1.4.0 — 2026-09-11

Frost pins the live desktop in the room and milks the far edge as the lid closes. Glass still freezes; Duo+ still leans as a hinged sheet.

The pane follows the hinge at display refresh. Sparse lid-sensor samples are coasted and critically damped so a real close feels like Preview instead of a 10 Hz staircase.

## 1.3.3 — 2026-09-11

Close the settings window to leave the Dock. The lid fold keeps running from a menu bar extra; quit from there to stop capture.

## 1.3.2 — 2026-09-11

Closing the settings window quits the app so it leaves the Dock and stops capture.

## 1.3.1 — 2026-09-11

Draw the fold over native full-screen apps (Safari, YouTube) without pulling them out of that Space.

## 1.3 — 2026-09-11

Leave the menu bar. Launch opens a System Settings–style window in the Dock; the lid fold still runs while the app is open.

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

## 1.1 — 2026-09-11

Keep the fold on the built-in display.

Configurable start/end lid angles, idle tick rate, and capture that stops after the freeze so switching screens does not hang or burn GPU.

## 1.0 — 2026-09-11

First public build.

- Menu-bar lid-fold on the built-in display
- Drag the app into Applications from the DMG
- Grant Screen Recording when asked
- Quit from the menu-bar panel so capture stops
