# AGENTS.md

Rules for AI coding agents working in this repository. People should read
[CONTRIBUTING.md](CONTRIBUTING.md); everything here applies to them too. The
`PR rules` check enforces the rules marked (checked); a pull request that
breaks one cannot be merged.

## What husk_sdk is

A Dart CLI (`bin/husk_sdk.dart`, `lib/src/`) that reads `husk.yaml` and
generates SwiftPM, CocoaPods, Gradle, Swift, Kotlin and Dart wiring that links
a closed-source vendor xcframework and AAR when present and a stub otherwise,
plus `doctor` and `check`, which inspect the binaries (`lib/src/inspect/`).
`example/acme_widget/` is a Flutter plugin wired by it;
`example/fake_vendor_sdk/` builds an invented SDK for it.

Read before you touch:

- generated files: the "Changing generated build files" section of
  CONTRIBUTING.md and `doc/how-it-works.md`. Everything `generate` writes
  comes from `lib/src/templates.dart`.
- toolchain quirks: `doc/traps.md` (SwiftPM manifest cache, `pod install`).
- binary inspection: `lib/src/inspect/` and `test/fixtures/README.md`.
- `husk.yaml` keys and defaults: `lib/src/spec.dart` and the "husk.yaml"
  section of the README.

## Commands

Use Dart 3.8 or newer for the tool. Every one of these must pass before you
open or update a pull request. CI runs the same ones:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
dart run husk_sdk -C example/acme_widget check     # example generated and wired
```

CI also builds the example for Android with Flutter 3.47.7 and Java 17,
without and then with the fake SDK:

```bash
(cd example/acme_widget/example && flutter build apk --debug)
example/fake_vendor_sdk/build.sh android
dart run husk_sdk -C example/acme_widget link --from example/fake_vendor_sdk/dist
dart run husk_sdk -C example/acme_widget check --require-sdk android
(cd example/acme_widget/example && flutter build apk --debug)
dart run husk_sdk -C example/acme_widget unlink    # back to the stub
```

The iOS simulator pair (`.github/workflows/ci.yml`, job `example-ios`) runs
on `main` only. Run one test file while iterating:
`dart test test/spec_test.dart`.

## Stop and ask the human

Some things must come from the real world. An agent must never invent them.
Stop and ask the person you work for to provide them:

- **Real build output.** A claim that a build succeeds, fails or links the
  vendor code needs a real `flutter build`, `xcodebuild`, `pod install` or
  Gradle run, with the Flutter, Xcode, CocoaPods and Android Gradle Plugin
  versions it used. Never write output you did not see.
- **Toolchain behaviour.** A template change cites the public Apple, Swift
  Package Manager, CocoaPods, Gradle, Android Gradle Plugin or Flutter
  document or issue it relies on. If you cannot find one, say so; do not
  guess.
- **Binary formats.** Mach-O, xcframework `Info.plist`, binary plist and AAR
  details come from the format's documentation or from a file made by the
  real tool (as `framework_info.bplist` was made with `plutil`). Never
  hand-write a fixture and claim a tool produced it.
- **An accepted issue.** If the change has no issue labelled `accepted`, stop
  and ask the human to open one and wait for a maintainer.

## Code

- **English only** for code, identifiers, comments, commit messages and docs.
  Answer the person you work for in their language.
- Target the minimum SDK in `pubspec.yaml` (Dart 3.8). The example plugin
  targets iOS 15.0 (`Package.swift`, podspec), Android minSdk 24 and JVM 17
  (`example/acme_widget/android/build.gradle.kts`); generated Swift and
  Kotlin must build there. Do not use features newer than that.
- Generated output stays deterministic: no timestamps, absolute paths or host
  names; a second `generate` changes nothing.
- Comments are sparse: only where the code is not self-evident. Do not add
  comments, doc comments or type annotations to code you did not change.

## Tests (checked)

- Every change to `lib/`, `bin/` or the Dart, Kotlin, Java or Swift sources
  of the projects under `example/` (generated ones included) comes with a
  test change under `test/` (or `example/acme_widget/test/`,
  `example/acme_widget/example/integration_test/`,
  `example/acme_widget/example/ios/RunnerTests/`, or an Android `src/test/`
  or `src/androidTest/` folder). A bug fix has a test that fails without the
  fix; check that it does before you open the pull request.
- A template change regenerates the example
  (`dart run husk_sdk -C example/acme_widget generate`) and commits the result.
- Fixtures and examples are invented: no real SDK, company or app names.
  Never commit a vendor binary, not even a fake one; `build.sh` makes them.

## Never

- Never silence the analyzer or a linter (checked): no `// ignore:`,
  `// ignore_for_file:`, `@Suppress(`, `@SuppressWarnings(`,
  `swiftlint:disable`, no changes to any `analysis_options.yaml`. Fix the
  finding instead.
- Never delete, skip, loosen or rewrite an existing test, expectation or
  fixture to make CI pass. If a test looks wrong, say so in the issue.
- Never change what users depend on without an issue that asks for it:
  command names, options and exit codes, `husk.yaml` keys and defaults, the
  `// GENERATED by husk_sdk` header and `BEGIN husk_sdk` / `END husk_sdk`
  markers, the `husk_vendor/` folders, `HUSK_SDK_DISABLE`, the `HUSK_<SDK>`
  compilation condition, the `<plugin>/husk` channel and `isAvailable()`.
- Never hand-edit a generated file in an example; change the template and
  regenerate.
- Never bump the version in `pubspec.yaml`, edit a released `CHANGELOG.md`
  section, publish, tag or release. Add your entry at the top of
  `CHANGELOG.md` under `## [Unreleased]` (create the heading if it is
  missing).
- Never add a dependency or change CI workflows unless the issue asks for it.
- Never add unrelated "improvements": no drive-by refactors, renames,
  reformatting of untouched code or dead code.
- Never open pull requests, issues or comments on your own. The human reviews
  your work and posts it.

## Pull requests (checked)

- First an issue, labelled `accepted` by a maintainer. The pull request says
  `Closes #N`.
- One issue per pull request, at most 400 changed lines.
- At most 2 open pull requests per person.
- Fill in the pull request template, including `### AI use` with the tool and
  model.
- The person submitting has read, run and understood every line, and writes
  the description in their own words. Pull requests that are raw, unreviewed
  agent output will be closed.
