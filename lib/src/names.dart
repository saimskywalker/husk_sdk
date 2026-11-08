/// Naming helpers, project paths, and the patterns every spec value is
/// checked against.
///
/// Spec values end up inside Swift, Ruby, Groovy, Kotlin and Dart source, so
/// they are restricted to characters that need no escaping in any of them.
library;

import 'package:path/path.dart' as p;

/// Name of the git-ignored directory that `link` copies vendor binaries into.
const String dropDirName = 'husk_vendor';

/// A Swift, Kotlin and Dart identifier.
final RegExp identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// A pub package name.
final RegExp dartPackageName = RegExp(r'^[a-z_][a-z0-9_]*$');

/// A version string such as `3.2.0` or `3.2.0-beta.1+5`.
final RegExp versionPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+-]*$');

/// A method channel name such as `acme_widget/husk`.
final RegExp channelPattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_./-]*$');

/// A Gradle property name.
final RegExp gradlePropertyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$');

/// A Kotlin package name.
final RegExp kotlinPackagePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

/// Maven `group:artifact:version` coordinates.
final RegExp mavenCoordinates = RegExp(
  r'^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+:[A-Za-z0-9_.+-]+$',
);

/// An xcframework file name (no directories).
final RegExp xcframeworkName = RegExp(
  r'^[A-Za-z0-9_][A-Za-z0-9_.+-]*\.xcframework$',
);

/// An AAR file name or a glob using `*` and `?` (no directories).
final RegExp aarGlob = RegExp(r'^[A-Za-z0-9_*?][A-Za-z0-9_.+*?-]*\.aar$');

/// Short description of [pattern] for error messages.
String describePattern(RegExp pattern) =>
    {
      identifier: 'an identifier like AcmeWidgetSDK',
      dartPackageName: 'a pub package name',
      versionPattern: 'a version like 3.2.0',
      channelPattern: 'a channel name like my_plugin/husk',
      gradlePropertyPattern: 'a Gradle property name',
      kotlinPackagePattern: 'a Kotlin package name',
      mavenCoordinates: 'group:artifact:version',
      xcframeworkName: 'a file name ending in .xcframework',
      aarGlob: 'a file name or glob ending in .aar',
    }[pattern] ??
    pattern.pattern;

/// Splits `AcmeWidgetSDK`, `acme_widget_sdk` or `acmeWidgetSdk` into
/// lower-case words: `[acme, widget, sdk]`.
List<String> splitWords(String name) {
  final spaced = name
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAll(RegExp(r'[_\-\s]+'), ' ')
      .trim();
  return [
    for (final w in spaced.split(' '))
      if (w.isNotEmpty) w.toLowerCase(),
  ];
}

/// `acme_widget_sdk`
String snake(List<String> words) => words.join('_');

/// `ACME_WIDGET_SDK`
String screamingSnake(List<String> words) => snake(words).toUpperCase();

/// `AcmeWidgetSdk`
String upperCamel(List<String> words) => words.map(_capitalize).join();

/// `acmeWidgetSdk`
String lowerCamel(List<String> words) {
  final upper = upperCamel(words);
  return upper.isEmpty ? upper : upper[0].toLowerCase() + upper.substring(1);
}

String _capitalize(String w) =>
    w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

/// Converts a file-name glob (`*`, `?`) to an anchored regular expression
/// source that means the same in Dart, Java and Ruby.
String globToRegExpSource(String glob) {
  final parts = glob.runes
      .map(String.fromCharCode)
      .map(
        (c) => switch (c) {
          '*' => '.*',
          '?' => '.',
          _ when RegExp(r'^[A-Za-z0-9_]$').hasMatch(c) => c,
          _ => '\\$c',
        },
      );
  return '^${parts.join()}\$';
}

/// Normalizes a user-supplied relative path to POSIX form.
///
/// Backslashes are treated as separators so a spec written on Windows works
/// everywhere. Absolute paths, drive letters and paths that climb out of the
/// project with `..` are rejected with a [FormatException].
String normalizeRelative(String input) {
  final raw = input.trim().replaceAll(r'\', '/');
  if (raw.isEmpty) throw const FormatException('must not be empty');
  if (raw.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(raw)) {
    throw const FormatException('must be relative to the project directory');
  }
  final normalized = p.posix.normalize(raw);
  if (normalized == '.' || normalized == '..' || normalized.startsWith('../')) {
    throw const FormatException('must point inside the project directory');
  }
  if (!RegExp(r'^[A-Za-z0-9_./+-]+$').hasMatch(normalized)) {
    throw const FormatException(
      'may only contain letters, digits and _ . / + -',
    );
  }
  return normalized;
}

/// [path] relative to [from], always with forward slashes, for messages and
/// generated files.
String displayPath(String path, {required String from}) =>
    p.split(p.relative(path, from: from)).join('/');
