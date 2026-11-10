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

Small, focused commits with clear messages, in English. Run the commands
above before pushing; every CI check must pass before a pull request can be
merged. The `PR rules` check enforces these:

- **Issue first.** Open an issue and wait until a maintainer labels it
  `accepted`, then write `Closes #N` in the pull request.
- **Tests.** Every change to `lib/`, `bin/` or the Dart, Kotlin, Java or
  Swift sources of the projects under `example/` needs a test change under
  `test/` (or an example's own test folder). A bug fix needs a test that
  fails without the fix.
- **Small.** At most 400 changed lines (lock files not counted), one issue
  per pull request.
- **No suppressions.** No `// ignore:`, `@Suppress(`, `@SuppressWarnings(` or
  `swiftlint:disable`, no changes to any `analysis_options.yaml`. Fix the
  finding.
- **At most 2 open pull requests** per person.

If a rule really does not fit your change, say why in the description. A
maintainer can waive it with a label (`no-tests-needed`, `large-change` or
`suppression-ok`).

## Legal notice

By submitting a contribution you confirm that you wrote it, that you have the
right to submit it, and that it may be distributed under the project license
(see [LICENSE](LICENSE)).

## AI-assisted contributions

Using AI tools is fine; please just be open about it.

- Say in the PR description which AI tools you used, if any: none, some or
  most, plus the tool or agent and the model (for example "Claude Code,
  Opus 5.5" or "Copilot, GPT-5").
- Please write the PR description in your own words; short and plain is fine.
  It shows us what you understood about the change. Please don't paste
  generated text.
- Read, run and test every line you submit, and be ready to explain it in
  review. If you don't understand what a line does, don't submit it.
- Keep the change focused. Agents like to add unrelated "improvements",
  long comments and dead code; remove them before you open the pull request.
- Pull requests that are raw, unreviewed agent output will be closed.
- If you use an agent, point it at [AGENTS.md](AGENTS.md).
- If the disclosure is missing, a check adds a reminder to the PR. It does
  not fail the PR, but a maintainer will ask about it before merging.

## Stay in touch

Don't forget to follow [@saimskywalker](https://github.com/saimskywalker) on
GitHub to see new releases and other open-source projects as they come out.
