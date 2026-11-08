# Toolchain traps

Facts about Swift Package Manager, CocoaPods, Gradle, the Android Gradle
Plugin and pub that shape how husk_sdk works. Each one was reproduced with
the example in this repository (Flutter 3.47, Xcode 27.2, CocoaPods 1.16,
Android Gradle Plugin 9.1) unless it says otherwise.

## Swift Package Manager

**`binaryTarget(path:)` must be relative to the package root.** An absolute
path fails with `invalid local path '...' for binary target 'X', path
expected to be relative to package root`. A relative path that climbs out
with `..` is accepted, which is how the generated manifest reaches a
directory named by an environment variable.

**The manifest is cached by its text and its environment, not by the files
it looks at.** SwiftPM stores evaluated manifests in
`~/Library/Caches/org.swift.swiftpm/manifests`. Adding or removing a binary
that the manifest checks with `FileManager` does not invalidate the entry,
and neither does `touch Package.swift` or deleting DerivedData. With the
example app:

- build without the SDK, `link`, build again: the second build succeeds
  and still contains the stub;
- build with the SDK, `unlink`, build again: resolution fails with
  `local binary target 'AcmeWidgetSDK' at '...' does not contain a binary
  artifact`.

Anything that changes the manifest text or the environment of the build
forces a fresh evaluation:

- `dart run husk_sdk link --clear-swiftpm-cache` (or `unlink`), which
  deletes the cache directory above;
- set or change any environment variable for the build, for example
  `HUSK_SDK_STATE=linked flutter build ios ...` (only the difference from
  the cached evaluation matters, not the name);
- point `$ACME_WIDGET_SDK_DIR` at the vendor directory instead of using
  `husk_vendor/`, so linking and unlinking change the environment anyway.

**`Package.swift` sees `Context.environment` of the process that resolves
packages.** `flutter build` and `xcodebuild` started from a shell pass the
shell's variables. An app started from the Dock or Finder gets the login
session's environment, not variables exported in a shell profile (general
macOS behaviour, not reproduced here); use `husk_vendor/` when working in
the Xcode app.

**Manifests need `import Foundation` for `FileManager` and `URL`.** An
`import` may appear anywhere at the top level of the file, which lets a
block appended to an existing manifest bring its own. Output printed by a
manifest shows up as a warning in every resolution.

**`#if canImport(Module)` answers what the compiler can find, not what the
target declared.** A module left in a shared build directory from an
earlier build can satisfy it. A compilation condition set with
`.define(...)` on the targets that link the binary is exact.

**Top-level code in a manifest runs in order.** A global used by
`Package(...)` must be declared above it; code that changes `package`
after the fact must come below it.

## CocoaPods

**`vendored_frameworks` paths are relative to the pod root,** the directory
of the podspec for a `:path` pod (Flutter's case). An absolute path fails
validation during `pod install` with `File patterns must be relative and
cannot start with a slash (vendored_frameworks)`; the podspec is Ruby, so `File.exist?` and `ENV` work in it.

**`..` out of a symlinked pod root is ambiguous.** Flutter's Podfile
points at plugins through `ios/.symlinks/plugins/<name>/ios`. A
`vendored_frameworks` path that climbs out of that directory with `..`
resolves textually in some places and through the symlink in others: in
the example, a path computed textually passed `pod install` and then the
compiler failed with `Unable to resolve module dependency`; a path
computed from the resolved directory made the podspec's own existence
check miss the framework. Keeping the framework inside the pod root
avoids both.

**`pod install` re-reads podspecs, `flutter build` does not always run
it.** Flutter skips `pod install` when its inputs (Podfile, lock file,
plugin list) have not changed. A binary appearing or disappearing is not
one of those inputs: in the example, `link` followed by `flutter build ios`
succeeded and still contained the stub; after `pod install` in the app's
`ios/` folder the next build linked the SDK. Run `pod install` (or
`flutter clean`) after `link` or `unlink`.

**One pod is one module.** Sources that SwiftPM builds as a separate
target end up in the plugin's module under CocoaPods, so an `import` of
that separate module must be guarded.

## Android Gradle Plugin and Gradle

**A library module cannot depend on a local `.aar` file directly.**
`implementation files('vendor.aar')` fails in the library's
`bundleDebugAar` / `bundleReleaseAar` task with `Direct local .aar file
dependencies are not supported when building an AAR`. Flutter runs that
task for every plugin, so the failure shows up in a normal app build. A
`flatDir` or Maven repository turns the file into a module dependency,
which is allowed; the resulting plugin AAR references the vendor library
instead of containing it.

**The app resolves the plugin's dependencies.** A repository added only to
the plugin project is not enough; the app project needs it too. Flutter's
app template evaluates `:app` before plugin projects, and adding
repositories to it later is fine as long as nothing has been resolved yet.
A settings file that sets `repositoriesMode` to `FAIL_ON_PROJECT_REPOS`
forbids project repositories; declare the repository in
`dependencyResolutionManagement` instead.

**The Android Gradle Plugin's built-in Kotlin compiles only `kotlin`
source directories.** With AGP 9's built-in Kotlin, the default for a new
app, a directory added with `sourceSets.main.java.srcDir(...)` is not
compiled as Kotlin (`compileDebugKotlin` reports `NO-SOURCE`); the Kotlin
Gradle plugin compiles Kotlin in both. Native mode's `husk.gradle` adds the
shim directory with `kotlin.srcDir(...)`, which both read.

**Kotlin has no conditional compilation.** Choosing between source
directories at configuration time is the closest equivalent; both
directories must declare the same API.

**Relative paths in Gradle properties resolve against the project that
reads them.** husk.gradle resolves them against the root project, which
for a Flutter app is the app's `android/` folder (where its
`gradle.properties` lives). Absolute paths avoid the question.

**`providers.gradleProperty` sees `-P` values and `gradle.properties`
entries** at configuration time; `flutter build apk -P name=value`
forwards `-P` to Gradle.

## xcframeworks

**Simulator builds on Apple silicon need an `arm64` simulator slice.** An
xcframework whose simulator slice is `x86_64` only links on Intel Macs or
under Rosetta.

**Static and dynamic frameworks behave differently.** A static framework
is linked into the binary that uses it and needs no embedding or signing.
A dynamic one is embedded in the app and must be signed for device builds.
The `ar` signature (`!<arch>`) or Mach-O file type in the framework binary
tells them apart; `doctor` reports which one a vendor shipped.

**Framework `Info.plist` files are often binary property lists**, not XML.
Tools that read them need to handle both.

## pub

**A `.pubignore` file replaces `.gitignore` for publishing.** A package
that has one publishes files git ignores unless `.pubignore` lists them
too. `generate` keeps the `husk_vendor/` entries in both.

## Windows

**Creating symbolic links needs Developer Mode or elevated rights.** `link`
copies a link's target instead of recreating the link on Windows.

**`core.autocrlf` turns `\n` into `\r\n` on checkout.** A generator that
always writes `\n` makes every generated file look modified there;
husk_sdk keeps the line endings a file already has.
