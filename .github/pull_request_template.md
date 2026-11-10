## What this changes

<!-- One or two sentences. Link the issue it fixes, e.g. "Closes #123". -->

## Checklist

- [ ] `dart format --output=none --set-exit-if-changed .` and `dart analyze --fatal-infos` are clean
- [ ] `dart test` passes
- [ ] Closes an issue labelled `accepted`; at most 400 changed lines; no `// ignore:`, `@Suppress(` or `swiftlint:disable` (checked)
- [ ] Changes to `lib/`, `bin/` or the example's sources come with a test (checked)
- [ ] If this fixes a bug: there is a test that fails without the fix
- [ ] Changed generated build files: `dart run husk_sdk generate` re-run in `example/acme_widget`, and the example builds with and without the fake SDK
- [ ] User-visible change: `CHANGELOG.md` entry
- [ ] Linked issue:

### AI use

<!-- Using AI is welcome. Please tick one, naming the tool and model if you used AI; a reminder appears if it is missing. See CONTRIBUTING.md. -->

- [ ] None
- [ ] Some (tool or agent, and model: ...)
- [ ] Most (tool or agent, and model: ...)
- [ ] I have read and tested every line.
