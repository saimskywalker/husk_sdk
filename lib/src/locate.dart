import 'dart:io';

import 'package:path/path.dart' as p;

import 'names.dart';
import 'spec.dart';

/// Where a vendor binary was found: the absolute native path of the
/// `.xcframework` directory or `.aar` file, and how it was found, e.g.
/// `$ACME_WIDGET_SDK_DIR` or `husk_vendor/`.
typedef Located = ({String path, String via});

/// The directories to search, in order: the one named by `--from` or else by
/// the spec's environment variable, then [dropDir] when [includeDropDir].
///
/// A `--from` path is relative to the working directory; an environment
/// path is relative to [relativeTo], mirroring what the generated build
/// files do.
List<Located> _searchDirs(
  HuskSpec spec,
  Map<String, String> env, {
  required String? from,
  required String relativeTo,
  required String dropDir,
  required bool includeDropDir,
}) {
  final value = env[spec.envVar];
  return [
    if (from != null && from.isNotEmpty)
      (path: p.normalize(p.absolute(from)), via: '--from')
    else if (value != null && value.isNotEmpty)
      (path: p.normalize(p.join(relativeTo, value)), via: '\$${spec.envVar}'),
    if (includeDropDir) (path: spec.resolve(dropDir), via: '$dropDir/'),
  ];
}

/// Finds the xcframework the way the generated `Package.swift` does.
Located? locateXcframework(
  HuskSpec spec,
  Map<String, String> env, {
  String? from,
  bool includeDropDir = true,
}) {
  final ios = spec.ios;
  if (ios == null) return null;
  final dirs = _searchDirs(
    spec,
    env,
    from: from,
    relativeTo: spec.resolve(ios.packageDir),
    dropDir: ios.dropDir,
    includeDropDir: includeDropDir,
  );
  for (final dir in dirs) {
    final path = p.join(dir.path, ios.xcframework);
    if (File(p.join(path, 'Info.plist')).existsSync()) {
      return (path: path, via: dir.via);
    }
  }
  return null;
}

/// All AARs in [dir] matching the spec's glob, sorted by name.
List<String> matchingAars(HuskSpec spec, String dir) {
  final glob = spec.android?.aar;
  final d = Directory(dir);
  if (glob == null || !d.existsSync()) return const [];
  final pattern = RegExp(globToRegExpSource(glob));
  return [
    for (final e in d.listSync())
      if (e is File && pattern.hasMatch(p.basename(e.path))) e.path,
  ]..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
}

/// Finds the AAR the way the generated `husk.gradle` does (the Gradle
/// property, which only Gradle can read, aside). Returns the chosen file
/// and every other match in the same directory.
(Located, List<String>)? locateAar(
  HuskSpec spec,
  Map<String, String> env, {
  String? from,
  bool includeDropDir = true,
}) {
  final android = spec.android;
  if (android == null || android.aar == null) return null;
  final dirs = _searchDirs(
    spec,
    env,
    from: from,
    relativeTo: spec.root,
    dropDir: android.dropDir,
    includeDropDir: includeDropDir,
  );
  for (final dir in dirs) {
    final matches = matchingAars(spec, dir.path);
    if (matches.isNotEmpty) {
      final last = matches.removeLast();
      return ((path: last, via: dir.via), matches);
    }
  }
  return null;
}
