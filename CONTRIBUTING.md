# Contributing

Thanks for helping Flutter plugins build with or without a closed-source
native SDK. The most valuable contributions are **fixes for toolchain
versions that break the generated files** (a new Xcode, CocoaPods, Android
Gradle Plugin or Flutter release) and **doctor/check findings that catch a
broken setup before a build does**.

## Development

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

CI runs these on the minimum supported SDK (3.8.0) and a pinned current
stable, with `dart format --output=none --set-exit-if-changed .` (on the
pinned stable only) in place of `dart format .`.

## Changing generated build files

Everything `generate` writes comes from `lib/src/templates.dart`. When you
change a template:

1. **Link the source.** Say in the PR which public Apple, Swift Package
   Manager, CocoaPods, Gradle, Android Gradle Plugin or Flutter document (or
   public issue) the change relies on.
2. **Keep the output deterministic.** No timestamps, absolute paths, host
   names or anything else that differs between machines. Running `generate`
   twice must change nothing.
3. **Regenerate the example**: `dart run husk_sdk -C example/acme_widget
   generate`, and commit the result.
4. **Build the example both ways.** Build the fake SDK with
   `example/fake_vendor_sdk/build.sh`, then build `example/acme_widget/example`
   for the iOS simulator and Android (debug) with the SDK linked
   (`dart run husk_sdk -C example/acme_widget link --from
   example/fake_vendor_sdk/dist`) and without it (`... unlink`). Say in the
   PR which toolchain versions you used.

Fixtures and examples must be invented: no real SDK, company or app names.
Never commit a vendor binary, not even a fake one; `build.sh` makes them.

## Pull requests

Small, focused commits with clear messages. Run the commands above before
pushing.

## AI-assisted contributions

Using AI tools is fine; please just be open about it.

- Say in the PR description which AI tools you used, if any: none, some or
  most, plus the tool or agent and the model (for example "Claude Code,
  Opus 5.5" or "Copilot, GPT-5").
- Write the PR description and any issues yourself, in your own words. Short,
  plain descriptions are welcome; please don't paste generated text.
- Read, run and test every line you submit, and be ready to explain it in
  review.
- PRs without the disclosure may be closed.

## Stay in touch

Don't forget to follow [@saimskywalker](https://github.com/saimskywalker) on
GitHub to see new releases and other open-source projects as they come out.
