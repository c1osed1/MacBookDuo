<div align="center">
  <img src="docs/icon.png" width="144" height="144" alt="MacBook Duo">
  <h1>MacBook Duo</h1>
  <p>
    <a href="https://github.com/c1osed1/MacBookDuo/actions/workflows/ci.yml"><img src="https://github.com/c1osed1/MacBookDuo/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
    <a href="https://github.com/c1osed1/MacBookDuo/releases"><img src="https://img.shields.io/github/v/release/c1osed1/MacBookDuo?include_prereleases&label=release" alt="Release"></a>
  </p>
  <p>
    App that plays the <strong>iPhone Duo lid-fold</strong> on a MacBook:
    when the lid closes, the built-in display recedes in 3D — <strong>Glass</strong>
    freezes one frame, <strong>Duo+</strong> keeps the live desktop and warps it
    around the hinge — driven by the real lid, not a cut between screens.
  </p>
  <p>Opens a System Settings–style window. Close it to leave the Dock; the lid fold keeps running from the menu bar extra.</p>

  <table>
    <tr>
      <td align="center" width="50%">
        <p><strong>Glass</strong><br/><sub>Freezes one frame, then recedes</sub></p>
        <img src="docs/glass.gif" width="300" alt="Glass lid-fold on a MacBook">
      </td>
      <td align="center" width="50%">
        <p><strong>Duo+</strong><br/><sub>Live desktop, warped around the hinge</sub></p>
        <img src="docs/duo-plus.gif" width="300" alt="Duo+ lid-fold on a MacBook">
      </td>
    </tr>
  </table>
</div>

## Requirements

- MacBook with a lid-angle HID sensor (recent Apple silicon models)
- macOS 15 or later
- **Screen Recording** permission (capture starts only while the fold is
  visible and stops when you quit)

## Use

1. Build and launch. A settings window opens.
2. Grant Screen Recording when macOS asks.
3. Close the lid slowly, or click **Preview**.
4. Close the window to hide the Dock icon; quit from the menu bar extra so capture stops.

<p align="center">
  <img width="280" alt="MacBook Duo settings" src="https://github.com/user-attachments/assets/6dae323b-7ccd-4a2d-9b4b-6069d701d27b" />
</p>

**Look** switches Glass and Duo+. **Depth** (Glass) and the Duo+ sliders
control how far the pane recedes. Overlay is limited to the built-in
Liquid Retina display. See the [changelog](CHANGELOG.md).

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
2. `CaptureStream` takes the built-in display through ScreenCaptureKit:
   Glass freezes one frame and stops; Duo+ stays live.
3. `DuoEngine` / `Shaders.metal` draw the fold: Glass is a receding pane
   with Kawase blur; Duo+ inverse-homography warps the live picture around
   the hinge.

## Privacy

Capture never leaves the Mac. The stream is excluded from this app’s own
windows, runs only during a fold or preview, and is torn down on quit.

## License

Source is under the [MIT License](LICENSE). See [NOTICE](NOTICE) for trademark
notes. Not affiliated with Apple.
