# Release Checklist

Use a fresh copy of this checklist for each release. Replace `<version>` with the target semantic version and keep evidence in the GitHub release or a linked tracking issue.

## Preparation

- [ ] Confirm signing, notarization, and Homebrew credentials exist only as secrets in the protected GitHub `release` environment.
- [ ] Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; confirm `v<version>` matches the build metadata.
- [ ] Review user-facing changes, migration needs, privacy impact, and release notes.
- [ ] Run tests, Release build, analyzer, strict-concurrency build, plist validation, and secret scan on Apple Silicon and Intel runners.
- [ ] Run the Thread Sanitizer network stress suite.
- [ ] Confirm idle CPU stays below 1%, 30-minute memory growth stays below 10 MiB, and first color-editor stall stays below 50 ms.
- [ ] Verify 64 KiB frame and 1,000 discovery-packet stress tests do not crash, hang, or grow state without bound.

## Signed artifact

- [ ] Produce the DMG through the protected `release` environment.
- [ ] Smoke-test the notarized DMG on a clean macOS 13 account and the current macOS release, on Apple Silicon and Intel.
- [ ] Test two real Yeelight capability profiles, device trust, endpoint changes, offline/reconnect, sleep/wake, and network changes.
- [ ] Test settings import/export and Launch at Login in the signed and sandboxed build.
- [ ] Test minimum/default/wide Settings layouts, light/dark appearance, keyboard navigation, and VoiceOver.
- [ ] `codesign --verify --deep --strict` passes for the app.
- [ ] Entitlements contain sandbox, network client/server, and user-selected read-write; Release omits `get-task-allow`.
- [ ] `hdiutil verify`, DMG signature verification, `stapler validate`, and Gatekeeper assessment pass.
- [ ] Notarization is `Accepted` and the notary log has no issues.
- [ ] Published SHA-256 matches the DMG and Homebrew cask exactly; the sidecar records only the DMG basename.
- [ ] GitHub artifact attestation verifies against the downloaded DMG.
- [ ] dSYM is retained only as an access-controlled workflow artifact.
- [ ] Temporary keychain and credentials are deleted even on failure.

## Publication

- [ ] Create the GitHub release as a draft, attach all assets, and publish it only after verification.
- [ ] Confirm repository release immutability is enabled before publishing the release.
- [ ] Mark release candidates as prereleases; mark stable semantic versions as latest.
- [ ] Update `bekircem/homebrew-yeelightbar` and test fetch, install, upgrade, uninstall, and optional zap.
- [ ] Verify the release page, README links, privacy statement, private security-advisory link, and user-facing release notes.
- [ ] Confirm the Homebrew checksum is identical to the final stapled DMG checksum.

## Post-release

- [ ] Verify the public DMG from a clean download rather than a local build output.
- [ ] Confirm GitHub and Homebrew installation instructions work without Gatekeeper bypasses.
- [ ] Keep failed runs for audit history, but delete merged branches and close obsolete draft releases.
- [ ] Monitor issues and private security advisories for regressions.
