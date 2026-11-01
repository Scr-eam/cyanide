<p align="center">
  <a href="README.md">简体中文</a> | <strong>English</strong>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/hxhlb/cyanide/main/Cyanide/Assets.xcassets/AppIcon.appiconset/icon-ios-1024x1024.png" alt="Cyanide" width="160">
</p>

<h1 align="center">Cyanide</h1>

<p align="center">
  A sideloadable iOS tweak runner built on the DarkSword kernel read/write primitive.
</p>

<p align="center">
  <a href="https://github.com/hxhlb/cyanide/releases/latest"><img src="https://img.shields.io/github/v/release/hxhlb/cyanide?label=release" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="AGPL-3.0 license"></a>
</p>

Cyanide combines the DarkSword kernel exploit chain with an Installer-style
interface and RemoteCall-based SpringBoard tweaks. It is not a traditional
jailbreak: most runtime tweaks are applied from the app and remain active only
for the current SpringBoard session, while a smaller set of tools intentionally
write persistent files or preferences.

This repository is the actively developed [`hxhlb/cyanide`](https://github.com/hxhlb/cyanide)
fork of the original [`zeroxjf/cyanide`](https://github.com/zeroxjf/cyanide)
project.

## Compatibility

The current exploit window is:

- iOS/iPadOS 17.0 through 18.7.1
- iOS/iPadOS 26.0 through 26.0.1
- A19 and M5 devices are not supported

The kernel bugs used by Cyanide, `CVE-2025-43510` and `CVE-2025-43520`, were
fixed in iOS/iPadOS 18.7.2 and 26.1. SpringBoard private APIs also vary between
releases, so an OS version being inside the exploit window does not guarantee
that every tweak works on that version or device.

## Install

Download the latest unsigned IPA from
[`GitHub Releases`](https://github.com/hxhlb/cyanide/releases/latest), then sign
and install it with your preferred sideloading tool.

You can also add the Cyanide AltStore source:

<p align="center">
  <a href="https://celloserenity.github.io/altdirect/?url=https://raw.githubusercontent.com/hxhlb/cyanide/main/source.json">
    <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/AltSource_Blue.png?raw=true" alt="Add AltSource" width="200">
  </a>
  <a href="https://github.com/hxhlb/cyanide/releases/latest">
    <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download IPA" width="200">
  </a>
</p>

## Highlights

### Tweak runner

- Installer-style package browser, queue, settings, logs, and local file sharing
- Compatibility groups that identify conflicting tweaks and prevent them from
  being queued together
- Kernel read/write setup, app sandbox escape, and SpringBoard RemoteCall support
- Runtime cleanup and session recovery for supported tweaks
- QuickLoader and RepoTweaks for local or repository-hosted JavaScript tweaks

### Built-in Tweaks

| Category | Tweak | What it does |
|---|---|---|
| Status Bar | StatBar | Uses a separate overlay window to show battery temperature, free memory, CPU, and network information near the status bar |
| Status Bar | NSBar | Uses a separate overlay window to show live upload and download speeds at the top of the screen |
| Status Bar | NiceBar Lite | Uses a separate overlay window to show custom text, date, weather, and system information in configurable positions at the top of the screen |
| Home Screen | SBCustomizer | Changes Dock capacity and the Home Screen grid, with an option to hide icon labels |
| Home Screen | Home Layout Extras | Adjusts Home Screen and Dock insets and icon scaling |
| Home Screen | Gravity Lite | Adds gravity, collision, bounce, and device-tilt physics to Home Screen icons |
| Home Screen | Watch Layout | Provides a scrolling Apple Watch-style honeycomb layout for browsing and launching apps |
| Home Screen | Cylinder Lite | Adds multiple page-level transition animations to Home Screen swipes |
| Home Screen | Hide Home Bar | Hides the bottom Home Bar; applying or restoring it requires a respring |
| Theming | SnowBoard Lite | Imports and applies local SnowBoard/IconBundles-style icon themes |
| Theming | LiveWP | Plays a local video as the Home and Lock Screen wallpaper |
| Theming | Metal Lock Light | Renders adjustable metallic lighting over the Lock Screen wallpaper |
| Theming | Mood Wallpaper | Switches between still wallpapers based on left and right device tilt |
| SpringBoard | Axon Lite | Groups Notification Center requests by app |
| SpringBoard | Dynamic Stage Lite | Presents two movable and resizable app windows over SpringBoard |
| SpringBoard | MilkyWay Lite | Runs multiple apps in movable and resizable floating windows |
| SpringBoard | iPad Dock | Enables the iPad-style Dock and its App Library entry on iPhone |
| SpringBoard | App Switcher Grid | Changes the system app switcher to a grid layout |
| SpringBoard | UIKit Debug Overlay | Opens UIKit's hierarchy debugging overlay by double-tapping the status bar |
| SpringBoard | Upside Down | Allows SpringBoard and apps to use the upside-down orientation |
| SpringBoard | FastLockX Lite | Provides Face ID retry and automatic unlock controls |
| SpringBoard | Disable App Library | Removes the App Library page after the final Home Screen page |
| SpringBoard | Disable Icon Fly-In | Skips the icon fly-in animation after unlock or returning Home |
| SpringBoard | Zero Wake Animation | Removes the display wake fade-in animation |
| SpringBoard | Zero Backlight Fade | Removes the backlight fade during lock and unlock |
| SpringBoard | Double-Tap to Lock | Locks the device after a double-tap on empty Home Screen space |
| SpringBoard | Drag Coefficient | Changes the global UIKit animation speed in SpringBoard |
| System | Powercuff | Limits CPU/GPU performance through simulated thermal pressure until reboot |

### JavaScript Tweaks

| Feature | What it does |
|---|---|
| QuickLoader | Imports and runs local `.js` tweaks |
| RepoTweaks | Downloads, configures, runs, and cleans up JavaScript tweaks from HTTPS sources |

### Tools and Persistent Changes

| Tool | What it does |
|---|---|
| MobileGestalt Editor | Edits selected device identity, model, and capability values |
| IPA Decryptor (beta) | Exports an installed app with its main executable decrypted; embedded frameworks, extensions, and dylibs may remain encrypted |
| App Downgrade | Uses a configurable version-history service to find and install older App Store releases |
| App Update Blocking | Creates or removes App Store update-blocking markers for selected apps |
| Location Simulator | Simulates a static CoreLocation coordinate |
| Watch Pairing Override | Changes the watchOS pairing compatibility range stored on the device |
| Call Recording Sound | Replaces or restores the call-recording start and stop disclosure sounds |
| OTA Updates | Disables or restores the system OTA update jobs |

### In Development

| Tweak | Current status |
|---|---|
| Signal Readouts | Numeric cellular/Wi-Fi signal display; currently not installable |
| TypeBanner | iMessage typing-status banner; currently not installable |
| Notification Island | Mirrors notification banners into the Dynamic Island; currently not installable |

Some packages are experimental, device-specific, or intentionally disabled
while incomplete. The tables describe feature scope, not verified support on
every OS release. The in-app package description and warning are the source of
truth for each feature. See [`RELEASE_NOTES.md`](RELEASE_NOTES.md) for recent
user-visible changes and
[`docs/TWEAK_COMPATIBILITY.md`](docs/TWEAK_COMPATIBILITY.md) for system-resource
ownership and conflict details.

## Safety

Cyanide uses a kernel exploit, private APIs, and runtime method replacement.
SpringBoard restarts, UI freezes, partial application, or a device reboot are
possible, especially on untested OS builds.

Read each package warning before applying it. Runtime tweaks are generally
restored by Cyanide's Clean Up action or by respringing, but tools that edit
system files, MobileGestalt values, or preferences can persist across a
respring or reboot. Keep backups of important data and do not test on a device
you cannot restore.

## Build

Requirements:

- macOS with a compatible Xcode and iPhoneOS SDK
- `xcbeautify` is optional; the build script falls back to raw `xcodebuild`
- `ldid` is required only for the VPhone packaging path

Build an unsigned device IPA:

```sh
./scripts/build.sh
```

The script writes `build/Cyanide-<version>.ipa` and updates
`build/Cyanide.ipa` to point to the latest build.

For a simulator build:

```sh
SDK=iphonesimulator ./scripts/build.sh
```

## JavaScript Tweaks

QuickLoader imports local `.js` files. RepoTweaks loads JavaScript packages
from HTTPS JSON repositories. Scripts run with powerful RemoteCall helpers, so
only use scripts and repositories you trust.

Scripts that change in-memory SpringBoard state should expose a synchronous
`globalThis.cleanup` function:

```js
globalThis.cleanup = function () {
  r_msg2_main(view, "setHidden:", 0);
  clearInterval(timer);
};
```

Cyanide invokes `cleanup()` when a supported script is disabled, removed, or
stopped during session cleanup. The function should restore only state owned by
that script and finish quickly. It cannot automatically reverse persistent file
or system changes.

## Contributing

Bug reports and focused pull requests are welcome:

- [Report a bug](https://github.com/hxhlb/cyanide/issues/new)
- [Open a pull request](https://github.com/hxhlb/cyanide/pulls)

When changing a private SpringBoard API path, include the tested device and OS
version. Keep compatibility fallbacks scoped because behavior differs sharply
between iOS releases.

## Credits

- [`zeroxjf`](https://github.com/zeroxjf): original Cyanide project and its
  Installer/Settings integration
- [`opa334`](https://github.com/opa334):
  [`darksword-kexploit`](https://github.com/opa334/darksword-kexploit), ChOma,
  and XPF
- [`wh1te4ever`](https://github.com/wh1te4ever):
  [`darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun)
  and the RemoteCall foundation
- [`rooootdev`](https://github.com/rooootdev): exploit reliability references
- [`kolbicz`](https://github.com/kolbicz): DarkSword tweaks and location
  simulation references
- [`d1y`](https://github.com/d1y): AGPL-3.0 implementations used by several
  Cyanide ports
- [`rpetrich`](https://github.com/rpetrich): Powercuff
- [`Julio Verne`](https://github.com/julioverne): Gravity
- [`tomt000`](https://github.com/tomt000): Dynamic Stage
- `Iggy05`: QuickLoader and RepoTweaks contributions
- `neonmodder123`: Web Respring method

Additional feature-specific credits are retained in the source and in-app
package descriptions.

## License

Cyanide is licensed under the [GNU Affero General Public License v3.0](LICENSE).
AGPL-covered code adapted from other projects remains under the same license.
