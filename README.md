<div align="center">
  <img src="docs/icon.png" width="144" height="144" alt="MacBook Duo">
  <h1>MacBook Duo</h1>
  <p>
    <a href="https://github.com/c1osed1/MacBookDuo/actions/workflows/ci.yml"><img src="https://github.com/c1osed1/MacBookDuo/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
    <a href="https://github.com/c1osed1/MacBookDuo/releases/latest"><img src="https://github.com/c1osed1/MacBookDuo/releases/latest/badge.svg" alt="Release"></a>
  </p>
  <p>
    Menu-bar app that plays the <strong>iPhone Duo lid-fold</strong> on a MacBook:
    when the lid closes, the built-in display recedes as a glass pane in 3D — blur,
    stretch, black bezels — driven by the real hinge, not a cut between screens.
  </p>
  <p>Lives in the menu bar only. No Dock window.</p>
</div>

## Requirements

- MacBook with a lid-angle HID sensor (recent Apple silicon models)
- macOS 15 or later
- **Screen Recording** permission (capture starts only while the fold is
  visible and stops when you quit)

## Use

1. Build and launch. A split-rectangle icon appears in the menu bar.
2. Grant Screen Recording when macOS asks.
3. Close the lid slowly, or click **Preview on screen**.
4. Quit from the menu-bar panel so capture actually stops (otherwise the
   system recording indicator can stick).

**Depth** controls how far the glass recedes. Overlay is limited to the
built-in Liquid Retina display.

## Build

```bash
xcodebuild -project MacBookDuo.xcodeproj -scheme MacBookDuo -configuration Debug
```

The target is signed with **Apple Development** so Screen Recording stays
granted across rebuilds. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) makes
TCC treat every build as a new app — do not switch back to that.

If you clone this repo, set `DEVELOPMENT_TEAM` in the Xcode target to your
own team, then sign in Xcode once.

## Releases

GitHub Actions builds on every push to `main`. A GitHub Release is published
only when the **tip commit** message contains `[RELEASE]`.

```bash
git commit -m "[RELEASE] 1.0.1 Tighten the menu bar popover"
git push origin main
```

- `[RELEASE] 1.2.0` (or `v1.2.0`) sets the tag to `v1.2.0`
- Bare `[RELEASE]` uses `MARKETING_VERSION` from the Xcode project
- You can also run the **Build** workflow by hand from the Actions tab

CI ships a **drag-to-Applications DMG** (ad-hoc signed). Gatekeeper may block
the first launch: right-click the app → Open. For daily use, build locally with
your Apple Development identity so Screen Recording permission survives rebuilds.

## How it works

1. `LidSensor` reads the hinge as an IOHID feature report (degrees, ~0 closed
   to ~180 open).
2. `CaptureStream` freezes a ScreenCaptureKit frame of the built-in display
   when a fold starts.
3. `DuoEngine` / `Shaders.metal` draw a perspective quad rotated around the
   bottom hinge, with Kawase blur and a circular glass falloff toward the top.

## Privacy

Capture never leaves the Mac. The stream is excluded from this app’s own
windows, runs only during a fold or preview, and is torn down on quit.

## License

Source is under the [MIT License](LICENSE). See [NOTICE](NOTICE) for trademark
notes. Not affiliated with Apple.
