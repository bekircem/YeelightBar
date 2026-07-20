# Release Readiness Report

Last verified: 2026-07-20 with Xcode 26.6 (macOS SDK 26.5).

## Current verdict

The source tree is ready for a signed `v1.0.0-rc.1` release-candidate build. It is not yet approved for a stable public release: Developer ID/notarization, clean-machine and real-bulb QA, Intel runtime verification, and the performance soak gates still require external environments or credentials.

No Critical or High security finding is known after the implemented hardening. This is a point-in-time assessment, not a guarantee that the software is defect-free.

## Verified locally

- 69 unit and integration tests pass with no failures.
- The 12-test TCP/network integration suite passes under Thread Sanitizer without a reported data race.
- Release build succeeds with complete Swift concurrency checking, with the Xcode toolchain warning noted below.
- Xcode static analyzer succeeds with no application-code diagnostic, with the same toolchain warning noted below.
- The unsigned Release executable contains both `arm64` and `x86_64` slices.
- Generated metadata contains bundle ID `io.github.bekircem.yeelightbar`, version `1.0.0` (build `1`), minimum macOS `13.0`, Utilities category, and `LSUIElement=true`.
- The privacy manifest is embedded in the app bundle.
- Plist, entitlement, workflow YAML, Homebrew template, and repository secret checks pass.
- Application source contains no `@unchecked Sendable`; the only occurrence is the test-only fake TCP server.

## Implemented release controls

- Actor-isolated connection and discovery state, session-generation validation, cancellation-aware reconnect/rate limiting, bounded TCP frames, and stale callback rejection.
- Explicit local-network device trust with source/Location checks, local-address validation, endpoint-change approval, candidate TTL/caps, and bounded untrusted strings/capabilities.
- Bounded and validated settings import with collision cleanup, background decoding, confirmation, and no reconnect before acceptance.
- Private/hash logging, remote-message sanitization, optimistic-state rollback, launch-at-login status reconciliation, and background color-wheel rendering.
- Sandboxed user-selected file access, privacy manifest, GPL-3.0 and project policy documents.
- SHA-pinned CI actions and a protected release workflow for universal archive/export, Developer ID signing, notarization, stapling, Gatekeeper checks, checksum, attestation, private dSYM retention, and stable-only Homebrew tap updates.

## Remaining release gates

1. Initialize/push the repository to `bekircem/YeelightBar`, enable branch protection and the protected `release` environment, and configure the secrets listed in `RELEASE_CHECKLIST.md`.
2. Run CI on both `macos-26` and `macos-26-intel`; inspect every warning and retain the run URL with the release evidence.
3. Resolve or formally account for two current Xcode 26 toolchain warnings: its bundled XCTest binaries declare macOS 14 while the required test target is macOS 13; and `appintentsmetadataprocessor` reports that extraction was skipped because the app intentionally has no AppIntents dependency, even though `ENABLE_APP_INTENTS_METADATA_EXTRACTION=NO`. No unnecessary AppIntents dependency was added merely to hide the latter warning. The application remains targeted at macOS 13 and compiler/analyzer code diagnostics are clean, but the strict zero-warning gate is not yet literally met with this Xcode version.
4. Produce `v1.0.0-rc.1` through the protected workflow and verify Developer ID signature, expected entitlements, absence of `get-task-allow`, accepted notarization, staple, Gatekeeper, DMG integrity, and artifact attestation.
5. Complete the clean macOS 13/current macOS, Apple Silicon/Intel, signed sandbox, Homebrew, accessibility, sleep/wake/network-change, and two-real-bulb smoke tests.
6. Record Instruments results for idle CPU, 30-minute memory growth, first color-editor stall, and discovery/frame stress limits.
7. Promote to `v1.0.0` only after every checkbox in `RELEASE_CHECKLIST.md` is closed with evidence.

## Suggested evidence retention

Attach the CI URLs, notarization result/log, DMG SHA-256, Homebrew cask commit, manual-QA matrix, and Instruments screenshots to the GitHub release or a linked release issue. Do not attach signing keys, API private keys, keychain exports, IP addresses, device IDs, or unsanitized diagnostics.
