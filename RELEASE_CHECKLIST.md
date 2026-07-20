# Release Checklist

## Release candidate

- [ ] Configure protected GitHub `release` environment approval and repository secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY_BASE64`, `RELEASE_KEYCHAIN_PASSWORD`, and a fine-grained `HOMEBREW_TAP_TOKEN` limited to the tap repository.
- [ ] Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; confirm tag/version match.
- [ ] Run all tests, Release build, analyzer, strict-concurrency build, plist validation, and secret scan on Apple Silicon and Intel runners.
- [ ] Run Thread Sanitizer network stress tests.
- [ ] Confirm idle CPU stays below 1%, 30-minute memory growth stays below 10 MiB, and first color editor stall stays below 50 ms.
- [ ] Verify 64 KiB frame and 1,000 discovery-packet stress tests do not crash, hang, or grow state without bound.
- [ ] Publish `v1.0.0-rc.1` as a GitHub prerelease from the protected `release` environment.
- [ ] Smoke-test the notarized DMG on a clean macOS 13 account and current macOS, Apple Silicon and Intel.
- [ ] Test two real Yeelight capability profiles, discovery trust, endpoint changes, offline/reconnect, sleep/wake, and network changes.
- [ ] Test settings import/export and Launch at Login in the signed+sandboxed build.
- [ ] Test minimum/default/wide Settings layouts, light/dark appearance, keyboard navigation, and VoiceOver.

## Artifact verification

- [ ] `codesign --verify --deep --strict` passes for the app.
- [ ] Entitlements contain sandbox, network client/server, and user-selected read-write; Release omits `get-task-allow`.
- [ ] `hdiutil verify`, DMG signature verification, `stapler validate`, and Gatekeeper assessment pass.
- [ ] Notarization is `Accepted` and the notary log is clean.
- [ ] Published SHA-256 matches the DMG and Homebrew cask exactly.
- [ ] dSYM is retained only as a private workflow artifact.
- [ ] Temporary keychain and credentials are deleted even on failure.

## Stable release

- [ ] All RC gates above passed with no unresolved release blocker.
- [ ] Publish `v1.0.0` and verify GitHub artifact attestation.
- [ ] Update `bekircem/homebrew-yeelightbar` and test install, upgrade, uninstall, and optional zap.
- [ ] Verify the GitHub release page, README links, privacy statement, security advisory link, and release notes.
