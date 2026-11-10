# husk_sdk example

`acme_widget/` is a Flutter plugin (from `flutter create --template=plugin`)
that wraps **AcmeWidgetSDK**, a fake closed-source SDK. `fake_vendor_sdk/`
holds its source and `build.sh`, which builds the binaries a vendor would
ship: `AcmeWidgetSDK.xcframework` (static, device and simulator slices) and
`acme-widget-3.2.0.aar`. Nothing in here is a real product.

What husk_sdk added to the plugin:

| File | |
|---|---|
| `husk.yaml` | the spec, written by `init` |
| `ios/acme_widget/Package.swift` | managed block: binary target when found, shim target always |
| `ios/acme_widget.podspec` | managed block: `vendored_frameworks` when found |
| `ios/acme_widget/Sources/AcmeWidgetSDKHusk/` | generated shim (`isAvailable`) |
| `ios/acme_widget/Sources/acme_widget/AcmeWidgetSDKHuskChannel.swift` | generated channel handler |
| `android/husk.gradle`, `android/build.gradle.kts` | generated script and the block that applies it |
| `android/src/husk/{linked,stub}/kotlin/` | generated shim, plus the hand-written `AcmeGreeter` twins |
| `android/src/main/kotlin/.../AcmeWidgetSDKHuskChannel.kt` | generated channel handler |
| `lib/src/acme_widget_sdk_husk.g.dart` | generated `AcmeWidgetSdkHusk.isAvailable()` |
| `.gitignore` | managed block for the `husk_vendor/` folders |

Hand-written: one registration line in each plugin class, and the vendor
calls guarded by `#if HUSK_ACMEWIDGETSDK` (Swift) or kept in
`src/husk/linked/` with a stub twin (Kotlin).

`native_app/` is the same SDK wired into a plain iOS and Android app
without Flutter (`mode: native`): a generated Swift package in
`ios/AcmeWidgetSDKHusk/` and `android/app/husk.gradle`, plus hand-written
`AcmeGreeter` twins.

Try it from the repository root:

```bash
# Without the SDK: builds the stub.
cd example/acme_widget/example
flutter build apk --debug
flutter build ios --simulator --no-codesign
cd -

# With the SDK.
example/fake_vendor_sdk/build.sh
dart run husk_sdk -C example/acme_widget link --from example/fake_vendor_sdk/dist --clear-swiftpm-cache
dart run husk_sdk -C example/acme_widget doctor
cd example/acme_widget/example
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

`--clear-swiftpm-cache` makes Swift Package Manager re-read `Package.swift`,
which it otherwise caches by text and environment. See `doc/traps.md`.
