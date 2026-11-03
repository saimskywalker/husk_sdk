# husk_sdk

Build a Flutter plugin or app **with or without** a closed-source native SDK.

Some native SDKs come as a binary you may not commit, publish or download
in CI: an `.xcframework` for iOS and an `.aar` (or a private Maven
artifact) for Android, with a licence, a size or credentials in the way.
The project still has to build and test for contributors, forks and CI that
do not have the binary, and link the real SDK on the machines that do.
Dart code needs to know at runtime which kind of build it is running in.

husk_sdk is a Dart command line tool that generates that wiring from a
small `husk.yaml`:

- **SwiftPM:** a block in the plugin's `Package.swift` that adds a
  `binaryTarget` when the xcframework is found, and a shim target either way;
- **CocoaPods:** a block in the podspec that sets `vendored_frameworks` when
  the xcframework is found;
- **Gradle:** `husk.gradle`, which links the AAR (or a Maven artifact) when
  found and compiles a stub source set otherwise;
- **Dart:** `AcmeWidgetSdkHusk.isAvailable()`, answered by generated Swift
  and Kotlin method channel handlers from what the native build linked;
- **CI:** `doctor` explains what was found (slices, architectures, version,
  static or dynamic, AAR manifest), `check` exits 0, 1 or 2.

The decision is made by the native build on the machine that runs it, so
the generated files are committed once and work everywhere. The vendor
binary is never committed.

husk_sdk is the successor to `imaji_binary_sdk`.

## Install

In the plugin (or app) that wraps the SDK:

```bash
dart pub add --dev husk_sdk
```

Requirements: Dart 3.8 or later for the tool. The generated files target
Flutter's plugin layout with Swift Package Manager and/or CocoaPods on iOS
and the Android Gradle Plugin with Kotlin on Android.

## A real run

The [example](example/) is a plugin made with `flutter create
--template=plugin` that wraps **AcmeWidgetSDK**, a fake SDK built locally by
`example/fake_vendor_sdk/build.sh` (a static xcframework with device and
simulator slices, and an AAR with one class). Everything below was run in
`example/acme_widget`.

### 1. Describe the SDK

```text
$ dart run husk_sdk init --sdk AcmeWidgetSDK --sdk-version 3.2.0 --aar 'acme-widget-*.aar'
Wrote husk.yaml.
Next: dart run husk_sdk generate
```

`husk.yaml` sets only what you passed; every default is written next to it
as a comment ([see the file](example/acme_widget/husk.yaml)).

### 2. Generate

```text
$ dart run husk_sdk generate
husk_sdk generate: AcmeWidgetSDK
  updated      ios/acme_widget/Package.swift
  created      ios/acme_widget/Sources/AcmeWidgetSDKHusk/AcmeWidgetSDKHusk.swift
  created      ios/acme_widget/Sources/acme_widget/AcmeWidgetSDKHuskChannel.swift
  updated      ios/acme_widget.podspec
  created      android/husk.gradle
  updated      android/build.gradle.kts
  created      android/src/main/kotlin/com/example/acme_widget/AcmeWidgetSDKHuskChannel.kt
  created      android/src/husk/linked/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  created      android/src/husk/stub/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  created      lib/src/acme_widget_sdk_husk.g.dart
  updated      .gitignore

Wire the generated channel into the plugin class:
  iOS:     call AcmeWidgetSDKHuskChannel.register(with: registrar) in register(with:)
  Android: call AcmeWidgetSDKHuskChannel.attach(binding.binaryMessenger) in onAttachedToEngine (and detach in onDetachedFromEngine)
```

Then add the one line per platform it asks for:

```swift
// ios/acme_widget/Sources/acme_widget/AcmeWidgetPlugin.swift, register(with:)
AcmeWidgetSDKHuskChannel.register(with: registrar)
```

```kotlin
// android/src/main/kotlin/.../AcmeWidgetPlugin.kt
AcmeWidgetSDKHuskChannel.attach(binding.binaryMessenger)   // onAttachedToEngine
AcmeWidgetSDKHuskChannel.detach(binding.binaryMessenger)   // onDetachedFromEngine
```

### 3. Without the SDK

```text
$ dart run husk_sdk doctor
husk_sdk doctor: AcmeWidgetSDK (plugin acme_widget)

iOS: AcmeWidgetSDK.xcframework
  info  not found: builds use the AcmeWidgetSDKHusk stub
         looked in $ACME_WIDGET_SDK_DIR (not set) and ios/acme_widget/husk_vendor/
  ok    channel registered in ios/acme_widget/Sources/acme_widget/AcmeWidgetPlugin.swift

Android: acme-widget-*.aar
  info  not found: builds use the AcmeWidgetSDKHusk stub
         looked in $ACME_WIDGET_SDK_DIR (not set) and android/husk_vendor/; Gradle also reads the property acmeWidgetSdkDir
  ok    channel registered in android/src/main/kotlin/com/example/acme_widget/AcmeWidgetPlugin.kt

Generated files
  ok    up to date: ios/acme_widget/Package.swift
  ok    up to date: ios/acme_widget/Sources/AcmeWidgetSDKHusk/AcmeWidgetSDKHusk.swift
  ok    up to date: ios/acme_widget/Sources/acme_widget/AcmeWidgetSDKHuskChannel.swift
  ok    up to date: ios/acme_widget.podspec
  ok    up to date: android/husk.gradle
  ok    up to date: android/build.gradle.kts
  ok    up to date: android/src/main/kotlin/com/example/acme_widget/AcmeWidgetSDKHuskChannel.kt
  ok    up to date: android/src/husk/linked/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  ok    up to date: android/src/husk/stub/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  ok    up to date: lib/src/acme_widget_sdk_husk.g.dart
  ok    up to date: .gitignore

Git
  ok    no vendor binaries are tracked

0 errors, 0 warnings.
```

`flutter build ios --simulator` and `flutter build apk --debug` both
succeed. The built apps contain the stub and no vendor code, and
`AcmeWidgetSdkHusk.isAvailable()` answers `false`.

### 4. With the SDK

```text
$ dart run husk_sdk link --from ../fake_vendor_sdk/dist --clear-swiftpm-cache
ios      copied ../fake_vendor_sdk/dist/AcmeWidgetSDK.xcframework -> ios/acme_widget/husk_vendor/
android  copied ../fake_vendor_sdk/dist/acme-widget-3.2.0.aar -> android/husk_vendor/

Cleared the Swift Package Manager manifest cache (~/Library/Caches/org.swift.swiftpm/manifests).
CocoaPods: run `pod install` in the app's ios/ folder.
```

```text
$ dart run husk_sdk doctor
husk_sdk doctor: AcmeWidgetSDK (plugin acme_widget)

iOS: AcmeWidgetSDK.xcframework
  ok    found via ios/acme_widget/husk_vendor/
         ios/acme_widget/husk_vendor/AcmeWidgetSDK.xcframework
         version 3.2.0, static
         ios-arm64_x86_64-simulator     ios simulator   arm64 x86_64
         ios-arm64                      ios             arm64
  ok    version matches husk.yaml (3.2.0)
  ok    channel registered in ios/acme_widget/Sources/acme_widget/AcmeWidgetPlugin.swift

Android: acme-widget-*.aar
  ok    found via android/husk_vendor/
         android/husk_vendor/acme-widget-3.2.0.aar
         version 3.2.0, package com.acme.widget, minSdk 21
  ok    version matches husk.yaml (3.2.0)
  ok    channel registered in android/src/main/kotlin/com/example/acme_widget/AcmeWidgetPlugin.kt

Generated files
  ok    up to date: ios/acme_widget/Package.swift
  ok    up to date: ios/acme_widget/Sources/AcmeWidgetSDKHusk/AcmeWidgetSDKHusk.swift
  ok    up to date: ios/acme_widget/Sources/acme_widget/AcmeWidgetSDKHuskChannel.swift
  ok    up to date: ios/acme_widget.podspec
  ok    up to date: android/husk.gradle
  ok    up to date: android/build.gradle.kts
  ok    up to date: android/src/main/kotlin/com/example/acme_widget/AcmeWidgetSDKHuskChannel.kt
  ok    up to date: android/src/husk/linked/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  ok    up to date: android/src/husk/stub/kotlin/com/example/acme_widget/AcmeWidgetSDKHusk.kt
  ok    up to date: lib/src/acme_widget_sdk_husk.g.dart
  ok    up to date: .gitignore

Git
  ok    no vendor binaries are tracked

0 errors, 0 warnings.
```

Builds now link the vendor binary (for CocoaPods, after `pod install`),
`isAvailable()` answers `true`, and the example's greeting comes from the
SDK.

### 5. In CI

`check` passes with the SDK linked, and fails once it is gone if the
pipeline requires it:

```text
$ dart run husk_sdk check --require-sdk ios --require-sdk android
husk_sdk check: AcmeWidgetSDK (plugin acme_widget)

0 errors, 0 warnings.
$ echo $?
0

$ dart run husk_sdk check --require-sdk ios
husk_sdk check: AcmeWidgetSDK (plugin acme_widget)

iOS: AcmeWidgetSDK.xcframework
  error not found: builds use the AcmeWidgetSDKHusk stub
         looked in $ACME_WIDGET_SDK_DIR (not set) and ios/acme_widget/husk_vendor/

1 error, 0 warnings.
$ echo $?
1
```

### Verified builds

The example app, `example/acme_widget/example`, built on macOS with
Flutter 3.47.7, Xcode 27.2, CocoaPods 1.16.2 and Android Gradle Plugin
9.1.0. "Vendor code" means the fake SDK's code was found in the built app
(`strings` on the iOS binary, the dex files of the APK).

| Build | Without the SDK | With the SDK |
|---|---|---|
| iOS simulator, Swift Package Manager (debug, no codesign) | builds, stub only | builds, vendor code linked (via `husk_vendor/` and via `$ACME_WIDGET_SDK_DIR`) |
| iOS simulator, CocoaPods (debug, no codesign) | builds, stub only | builds, vendor code linked (via `husk_vendor/`, after `pod install`) |
| Android APK (debug) | builds, no vendor classes | builds, vendor classes in the dex (via `husk_vendor/`, `$ACME_WIDGET_SDK_DIR` and `-P acmeWidgetSdkDir=...`) |

Each "with" build was followed by an `unlink` and a stub build again. The
CocoaPods builds used a separate app with Swift Package Manager turned off
(`flutter: config: enable-swift-package-manager: false`). CI repeats the
Android pair on every push and the iOS pair on `main`.

## Writing code against the SDK

**Swift.** The compilation condition `HUSK_ACMEWIDGETSDK` is defined on the
plugin target only when the xcframework was linked:

```swift
#if HUSK_ACMEWIDGETSDK
import AcmeWidgetSDK
#endif

case "greeting":
  #if HUSK_ACMEWIDGETSDK
  result(AcmeWidget.greeting(for: name))
  #else
  result(FlutterError(code: "vendor_sdk_missing", message: nil, details: nil))
  #endif
```

**Kotlin.** Kotlin has no `#if`, so `husk.gradle` adds one of two source
directories. Keep code that touches the vendor API in
`android/src/husk/linked/kotlin/` and a stub with the same signatures in
`android/src/husk/stub/kotlin/`:

```kotlin
// src/husk/linked/kotlin/com/example/acme_widget/AcmeGreeter.kt
internal object AcmeGreeter {
    fun greeting(name: String): String? = com.acme.widget.AcmeWidget.greeting(name)
}

// src/husk/stub/kotlin/com/example/acme_widget/AcmeGreeter.kt
internal object AcmeGreeter {
    fun greeting(name: String): String? = null
}
```

**Dart.**

```dart
if (await AcmeWidgetSdkHusk.isAvailable()) {
  // The native SDK is linked into this build.
}
```

`isAvailable()` is `false` on platforms without a native handler (web,
desktop, unit tests). In widget tests, mock the `<plugin>/husk` channel and
call `AcmeWidgetSdkHusk.resetForTesting()` between tests.

## Getting the binary to the build

| | iOS, SwiftPM | iOS, CocoaPods | Android |
|---|---|---|---|
| 1 | | | Gradle property (`-P acmeWidgetSdkDir=...`, `gradle.properties`) |
| 2 | `$ACME_WIDGET_SDK_DIR` | | `$ACME_WIDGET_SDK_DIR` |
| 3 | `ios/<plugin>/husk_vendor/` | `ios/<plugin>/husk_vendor/` | `android/husk_vendor/` |

`dart run husk_sdk link --from <dir>` (or with `$ACME_WIDGET_SDK_DIR` set)
copies the binaries into the git-ignored `husk_vendor/` folders, which
every build reads, the Xcode app included. `unlink` removes them. `HUSK_SDK_DISABLE=1`
forces the stub. A pipeline that downloads the SDK from a private store
typically runs:

```bash
dart run husk_sdk link --from "$RUNNER_TEMP/vendor"
dart run husk_sdk check --require-sdk ios --require-sdk android
```

After linking or unlinking, Swift Package Manager may reuse a cached
manifest (pass `--clear-swiftpm-cache`) and CocoaPods needs `pod install`;
see [doc/traps.md](doc/traps.md).

## Commands

```text
dart run husk_sdk [-C <dir>] <command> [options]
```

| Command | What it does | Exit codes |
|---|---|---|
| `init --sdk <Name>` | Writes a commented `husk.yaml`. Options: `--sdk-version`, `--aar`, `--android-package`, `--[no-]ios`, `--[no-]android`, `--force`. | 0, 1 if it exists, 2 |
| `generate` | Writes or updates the generated files. `--dry-run`, `--force` (overwrite files without the generated header). | 0, 1 if a file cannot be updated, 2 |
| `link` | Copies the binaries into `husk_vendor/`. `--from <dir>`, `--clear-swiftpm-cache`. | 0, 1 if nothing found, 2 |
| `unlink` | Deletes the `husk_vendor/` folders. `--clear-swiftpm-cache`. | 0, 2 |
| `doctor` | Prints everything it found. `--from <dir>`, `--json`. | 0, 2 |
| `check` | Prints warnings and errors. `--from <dir>`, `--require-sdk ios\|android` (repeatable), `--json`. | 0 fine, 1 errors, 2 usage or `husk.yaml` error |

`--json` prints `{"sections":[{"title","findings":[{"level","message","detail"}]}],"exitCode"}`. `exitCode` is the code `check` would use (0 or 1). `doctor` still exits 0.

`check` fails when a generated file is missing or out of date, a plugin
class does not register the generated channel, a found binary is broken
(no device or simulator slice, no `AndroidManifest.xml`), its version does
not match `sdk.version`, or a vendor binary is tracked by git.

## husk.yaml

```yaml
sdk:
  name: AcmeWidgetSDK          # Swift module name; required
  version: 3.2.0               # optional; check fails on a mismatch
plugin: acme_widget            # default: pubspec name
shim: AcmeWidgetSDKHusk        # generated Swift/Kotlin type and SwiftPM target
channel: acme_widget/husk      # method channel used by isAvailable()
binary:
  env: ACME_WIDGET_SDK_DIR     # directory with the vendor files
  gradle_property: acmeWidgetSdkDir
ios:                           # omit to skip iOS
  xcframework: AcmeWidgetSDK.xcframework
  package_dir: ios/acme_widget # holds Package.swift
  podspec: ios/acme_widget.podspec   # null to skip CocoaPods
  target: acme_widget          # the plugin's SwiftPM target
android:                       # omit to skip Android
  aar: 'acme-widget-*.aar'     # file name or glob; the last match by name wins
  # maven:                     # instead of aar
  #   coordinates: com.acme:widget:3.2.0
  #   url_property: acmeWidgetSdkMavenUrl
  #   url_env: ACME_WIDGET_SDK_MAVEN_URL
  #   username_property: acmeMavenUser
  #   password_property: acmeMavenPassword
  module_dir: android
  package: com.example.acme_widget   # default: namespace in build.gradle(.kts)
  source_dir: src/main/kotlin
dart:
  output: lib/src/acme_widget_sdk_husk.g.dart
  class: AcmeWidgetSdkHusk
```

All values above except `sdk.name` are the defaults for this SDK name and
plugin. Paths are relative to `husk.yaml` and may use `/` or `\`.

## Generated files

Owned files start with `// GENERATED by husk_sdk` and are rewritten as a
whole. Edits to files you own are confined to a `BEGIN husk_sdk` /
`END husk_sdk` block. Output is deterministic, a second `generate` changes
nothing, files are only written when their content changes, and CRLF files
stay CRLF. Commit all of it. [doc/how-it-works.md](doc/how-it-works.md)
explains each file.

## Limits and plan

- One SDK per `husk.yaml`. Several SDKs mean several plugins, or a future
  list form of the spec.
- iOS binaries must be xcframeworks; plain `.framework` and `.a` files are
  not handled.
- Android, iOS only: no macOS, Windows or Linux desktop targets yet.
- The Maven mode is covered by tests of the generated script, not by a
  build against a real repository in this repository's CI.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through
[SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE](LICENSE).
