# YeelightBar

YeelightBar is a native, menu-bar-only macOS controller for Yeelight-compatible lights on your local network. It provides power, brightness, temperature, color, reusable modes, color flows, favorites, and global shortcuts without a cloud account.

## Requirements

- macOS Ventura 13 or later
- A Yeelight-compatible Wi-Fi light with **LAN Control** enabled in the Yeelight mobile app
- The Mac and light on the same trusted local network

## Install

### Signed DMG

Download `YeelightBar-X.Y.Z.dmg` and its SHA-256 file from [GitHub Releases](https://github.com/bekircem/YeelightBar/releases). Open the DMG and drag YeelightBar to Applications.

### Homebrew

```sh
brew install --cask bekircem/yeelightbar/yeelightbar
```

The personal tap is updated only after a signed, notarized stable release completes.

## Build from source

```sh
xcodebuild \
  -project YeelightBar.xcodeproj \
  -scheme YeelightBar \
  -destination 'platform=macOS' \
  test
```

Open `YeelightBar.xcodeproj` in Xcode and press Command-R for local development. YeelightBar is an `LSUIElement` app: it intentionally has no Dock icon and appears in the macOS menu bar.

## Local network trust model

The Yeelight LAN protocol is plaintext and does not authenticate bulbs. Anyone with sufficient access to the same network may be able to observe traffic or impersonate a bulb. YeelightBar reduces this risk by accepting discovery only from private/link-local addresses, requiring discovery source and advertised endpoint to match, and requiring explicit user trust before first connection or endpoint changes.

Use YeelightBar only on a network you trust. The app cannot add encryption or authentication that the bulb protocol does not provide.

## Privacy

YeelightBar has no analytics, telemetry, advertising, cloud service, or crash-reporting SDK. Device endpoints and settings remain on the Mac unless you explicitly export a settings JSON file. See [PRIVACY.md](PRIVACY.md).

## Troubleshooting

- **No menu-bar icon:** Stop any older run, select the YeelightBar scheme, and press Command-R. Look near Control Center; macOS may hide menu-bar items when space is limited.
- **No bulb found:** Enable LAN Control, confirm both devices are on the same subnet, allow Local Network access, then choose **Discover Now**.
- **Discovered but not connected:** Approve the bulb under Settings → Devices. Discovery never auto-trusts a new endpoint.
- **Offline after sleep/network change:** Use Discover Now or select the bulb again. Reconnect work is cancellation-aware and scoped to the selected device.
- **Launch at Login needs approval:** Open System Settings → General → Login Items and approve YeelightBar.

Please remove device names and IP addresses before attaching diagnostics to a public issue.

## Security and contributions

Read [SECURITY.md](SECURITY.md) before reporting a vulnerability and [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Release owners should follow [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

## License and trademark

Copyright © 2026 bekircem. Source code is licensed under [GPL-3.0](LICENSE).

YeelightBar is an independent project and is not affiliated with, endorsed by, or sponsored by Yeelight. Yeelight and other marks belong to their respective owners.
