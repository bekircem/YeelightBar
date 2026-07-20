# Privacy

YeelightBar controls compatible lights directly over the local network. It does not use a cloud service.

## Data handled

The app stores trusted bulb identifiers, local IP endpoints, capability information, last-known light state, preferences, custom modes/flows, favorites, and keyboard shortcuts in its sandboxed macOS container. Export happens only when the user chooses an export destination.

## Data not collected

YeelightBar includes no analytics, advertising, telemetry, user account, cloud synchronization, or crash-reporting SDK. The developer does not receive app usage, device state, bulb identity, IP address, or diagnostics automatically.

## Network activity

The app sends SSDP-like discovery datagrams and Yeelight protocol commands on the local network. The Yeelight LAN protocol is plaintext and unauthenticated, so other parties with access to the same network may be able to observe or imitate this traffic.

## Diagnostics

Unified logs treat messages as private/hash-masked. The in-app diagnostic ring is bounded and sanitizes control characters and long remote messages. Review copied diagnostics before sharing them publicly.

## Deletion

Use Settings to forget devices or reset preferences. Uninstalling the app does not automatically remove its sandbox container; the Homebrew cask's optional `zap` stanza lists the bundle-ID-based preference and container locations.
