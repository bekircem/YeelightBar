# Contributing

Thanks for helping improve YeelightBar.

1. Open an issue for user-facing or architectural changes before investing in a large implementation.
2. Keep the app native, dependency-light, offline-first, sandboxed, and compatible with macOS 13.
3. Preserve persisted Codable fields, preset IDs, enum raw values, and `ColorFlow.expression` unless an explicit migration is included.
4. Add tests for behavior changes and run the full test, Release build, analyzer, strict-concurrency, plist, and secret checks.
5. Never commit Apple certificates, `.p12` files, API private keys, provisioning profiles, exported user preferences, device IDs, names, or IP addresses.
6. Submit focused pull requests with a clear risk assessment and manual QA notes.

By contributing, you agree that your contribution is licensed under GPL-3.0.
