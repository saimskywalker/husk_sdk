# Changelog

## [Unreleased]

- `doctor` and `check` accept `--json`. It prints the same report as JSON
  (`sections`, findings with `level`, `message` and `detail`, and the exit
  code `check` would use). Process exit codes are unchanged.
- The README snippet and the example plugin report a missing vendor SDK
  with the error code `vendor_sdk_missing` (was `sdk_unavailable`). The
  generated code is unchanged; plugins that copied the old code keep
  working.

## 0.1.0

First release.

- `husk.yaml` spec with defaults derived from the SDK name and the plugin
  (pubspec name, Gradle namespace); unknown keys and values that would need
  escaping in generated code are rejected.
- `init` writes a commented starter spec.
- `generate` writes, idempotently:
  - a block in `Package.swift` that adds the vendor `binaryTarget` and a
    `<Sdk>Husk` shim target when the xcframework is found, and the shim
    alone otherwise;
  - a block in the podspec that sets `vendored_frameworks` when the
    xcframework is in `husk_vendor/`;
  - `android/husk.gradle`, applied from the module's build file, that links
    the AAR (file or private Maven repository) or compiles a stub source
    set;
  - Swift and Kotlin method channel handlers and a Dart class with
    `isAvailable()`;
  - `.gitignore` (and `.pubignore`, when present) entries for the vendor
    drop folders.
- `link` / `unlink` copy the vendor binaries into git-ignored `husk_vendor/`
  folders, keeping symbolic links and permission bits;
  `--clear-swiftpm-cache` deletes Swift Package Manager's manifest cache so
  the next build notices the change.
- `doctor` reports what was found: xcframework slices, architectures,
  version and static or dynamic linkage; AAR package, version, minSdk and
  ABIs; generated file state; plugin wiring; vendor files tracked by git.
- `check` for CI: exit 0 when fine, 1 on problems, 2 on usage or spec
  errors; `--require-sdk ios|android` for builds that must link the SDK.
