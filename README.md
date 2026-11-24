# LarkBar

A small macOS menu bar app for **Hollyland Lark** wireless mics. Plug the Lark USB receiver into your
Mac and LarkBar shows each mic's battery in the menu bar and lets you change the receiver's
settings without your phone or the LarkSound app.

<img src="docs/screenshot-dark.png" width="340" alt="LarkBar menu with mic batteries, sound and receiver settings">

- Detects which Hollyland receiver is plugged in, and notices when you plug it in or pull it out.
- Battery level and on/off state for every mic, with the lowest battery shown in the menu bar.
- Mute each mic, set gain, noise cancelling, EQ, reverb, and mono/stereo.
- Receiver settings: auto power off, signal mode, status light, performance mode, identify, restart.
- Only shows the controls your receiver supports.
- Menu bar only: no Dock icon, no windows. Optional Open at Login.

LarkBar talks only to the receiver's control interface, so the mics keep working as an audio input
while it runs. It needs no special permissions and makes no network requests.

## Supported receivers

| Receiver | USB ID | Status |
| --- | --- | --- |
| Lark A1 (USB-C receiver) | `3547:0407` | Supported, tested on firmware 1.0.2.12 |
| Lark M2 (USB-C receiver) | `3547:0007` | Experimental: gain, noise cancelling, batteries, restart. Not tested on hardware yet |

Other Hollyland devices are detected and shown as unsupported, with a **Copy Device Info** button.
If you own one, [open an issue](https://github.com/rajatkapoor/larkbar/issues/new) with that info.

## Install

1. Download `LarkBar-<version>.dmg` from the [latest release](https://github.com/rajatkapoor/larkbar/releases/latest).
2. Open it and drag **LarkBar** into **Applications**.
3. Open LarkBar from Applications. A mic icon appears in the menu bar.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

**If macOS says it can't verify LarkBar**, the build you downloaded isn't notarized by Apple yet
(the release notes say so). Open **System Settings → Privacy & Security**, scroll down, and click
**Open Anyway** next to the LarkBar message. Or run:

```sh
xattr -dr com.apple.quarantine /Applications/LarkBar.app
```

## Build it yourself

You need Xcode 16 or later. No Apple Developer account is required.

```sh
git clone https://github.com/rajatkapoor/larkbar.git
cd larkbar
open LarkBar.xcodeproj   # then press ⌘R
```

Or from the terminal:

```sh
xcodebuild -project LarkBar.xcodeproj -scheme LarkBar -configuration Release \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/LarkBar.app
```

To package a DMG and zip like the official releases, without signing:

```sh
scripts/release.sh --unsigned   # output in build/release/<version>/
```

Run the tests with `xcodebuild -project LarkBar.xcodeproj -scheme LarkBar test`.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The generated project is committed, so you only need XcodeGen if you add or remove files
(`brew install xcodegen && xcodegen generate`).

## How it works

Lark receivers are composite USB devices: a standard USB audio interface for the mics, plus a
vendor HID interface that carries Hollyland's control protocol. LarkBar uses IOKit HID to send the
same 64-byte request/reply frames the LarkSound app does.

- `LarkBar/Devices/LarkProtocol.swift`: frame layouts for both protocol versions.
- `LarkBar/Devices/ReceiverStatus.swift`: settings, their wire encoding, and status parsing.
- `LarkBar/Devices/LarkModel.swift`: the list of known receivers. Adding a receiver that speaks an
  existing protocol is usually just a new entry here.
- `LarkBar/Devices/HollylandHID.swift`: device discovery and the IOKit transport.

The protocol was reverse-engineered by [larkctl](https://github.com/blchinezu/larkctl), a Linux CLI
for the same receivers. LarkBar is an independent Swift implementation.

## Contributing

Issues and pull requests are welcome, especially reports from owners of receivers other than the
Lark A1. For protocol changes, please add a test in `LarkBarTests` with a captured reply.

Maintainers: see [RELEASING.md](RELEASING.md) for cutting a release.

## License

MIT. See [LICENSE](LICENSE).

LarkBar is an unofficial project and isn't affiliated with or endorsed by Hollyland. Hollyland and
Lark are trademarks of their owner.
