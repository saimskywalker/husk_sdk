import 'dart:io';

import 'package:path/path.dart' as p;

import 'locate.dart';
import 'names.dart';
import 'spec.dart';

/// One binary copied (or removed) by `link` / `unlink`.
class LinkResult {
  /// Creates a result.
  LinkResult(this.platform, this.message, {this.ok = true});

  /// `ios` or `android`.
  final String platform;

  /// What happened.
  final String message;

  /// False when the binary was not found.
  final bool ok;
}

/// Copies the vendor binaries from [from] (or the spec's environment
/// variable) into the git-ignored drop directories.
///
/// The xcframework is copied with its symbolic links intact (macOS
/// framework bundles rely on them) into a temporary sibling first and then
/// renamed into place, so an interrupted copy never leaves a half-written
/// framework that the build would pick up.
List<LinkResult> link(
  HuskSpec spec, {
  required Map<String, String> env,
  String? from,
}) => [
  if (spec.ios case final ios?) _linkXcframework(spec, ios, env, from),
  if (spec.android case final android?)
    android.aar == null
        ? LinkResult(
            'android',
            'uses Maven (${android.maven!.coordinates}); nothing to copy',
          )
        : _linkAar(spec, android, env, from),
];

LinkResult _linkXcframework(
  HuskSpec spec,
  IosSpec ios,
  Map<String, String> env,
  String? from,
) {
  final found = locateXcframework(spec, env, from: from, includeDropDir: false);
  if (found == null) {
    return LinkResult(
      'ios',
      '${ios.xcframework} not found in ${_where(spec, env, from)}',
      ok: false,
    );
  }
  _replaceWith(found.path, p.join(spec.resolve(ios.dropDir), ios.xcframework));
  return LinkResult('ios', 'copied ${_show(found.path)} -> ${ios.dropDir}/');
}

LinkResult _linkAar(
  HuskSpec spec,
  AndroidSpec android,
  Map<String, String> env,
  String? from,
) {
  final found = locateAar(spec, env, from: from, includeDropDir: false);
  if (found == null) {
    return LinkResult(
      'android',
      'no file matching ${android.aar} in ${_where(spec, env, from)}',
      ok: false,
    );
  }
  final source = found.$1.path;
  final drop = spec.resolve(android.dropDir);
  // Drop older copies so Gradle cannot pick a stale version.
  for (final old in matchingAars(spec, drop)) {
    File(old).deleteSync();
  }
  _replaceWith(source, p.join(drop, p.basename(source)));
  return LinkResult(
    'android',
    'copied ${_show(source)} -> ${android.dropDir}/',
  );
}

/// Deletes Swift Package Manager's manifest cache under the user's home
/// directory (from [env]) and returns its path, or null when there is none
/// or the host is not macOS.
///
/// SwiftPM keys cached manifest evaluations on the manifest text and the
/// environment, so a manifest that looks for a binary on disk keeps its old
/// answer after the binary is added or removed. The cache is rebuilt on
/// the next resolution.
String? clearSwiftPmManifestCache(Map<String, String> env) {
  final home = env['HOME'];
  if (!Platform.isMacOS || home == null || home.isEmpty) return null;
  final dir = Directory(
    p.join(home, 'Library', 'Caches', 'org.swift.swiftpm', 'manifests'),
  );
  if (!dir.existsSync()) return null;
  dir.deleteSync(recursive: true);
  return dir.path;
}

/// Deletes the drop directories. Returns the ones that existed.
List<String> unlink(HuskSpec spec) {
  final removed = <String>[];
  for (final dir in [spec.ios?.dropDir, spec.android?.dropDir].nonNulls) {
    final d = Directory(spec.resolve(dir));
    if (!d.existsSync()) continue;
    d.deleteSync(recursive: true);
    removed.add(dir);
  }
  return removed;
}

/// [path] relative to the working directory when that is short.
String _show(String path) {
  final cwd = Directory.current.path;
  final ups = p.split(p.relative(path, from: cwd)).where((s) => s == '..');
  return ups.length <= 2 ? displayPath(path, from: cwd) : path;
}

String _where(HuskSpec spec, Map<String, String> env, String? from) {
  if (from != null) return from;
  final value = env[spec.envVar];
  return value == null || value.isEmpty
      ? '(no --from and \$${spec.envVar} is not set)'
      : '\$${spec.envVar} ($value)';
}

void _replaceWith(String source, String target) {
  final parent = Directory(p.dirname(target))..createSync(recursive: true);
  final temp = p.join(parent.path, '.${p.basename(target)}.husk-tmp');
  _delete(temp);
  copyTree(source, temp);
  _delete(target);
  final type = FileSystemEntity.typeSync(temp, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    Directory(temp).renameSync(target);
  } else {
    File(temp).renameSync(target);
  }
}

void _delete(String path) {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.notFound:
      break;
    case FileSystemEntityType.directory:
      Directory(path).deleteSync(recursive: true);
    case FileSystemEntityType.link:
      Link(path).deleteSync();
    default:
      File(path).deleteSync();
  }
}

/// Copies [from] to [to] recursively.
///
/// Symbolic links are recreated as links on macOS and Linux. On Windows,
/// where creating links usually needs extra privileges, the link target is
/// copied instead. File permission bits travel with each file copy.
void copyTree(String from, String to) {
  switch (FileSystemEntity.typeSync(from, followLinks: false)) {
    case FileSystemEntityType.link:
      if (Platform.isWindows) {
        copyTree(Link(from).resolveSymbolicLinksSync(), to);
      } else {
        Link(to).createSync(Link(from).targetSync());
      }
    case FileSystemEntityType.directory:
      Directory(to).createSync(recursive: true);
      for (final child in Directory(from).listSync(followLinks: false)) {
        copyTree(child.path, p.join(to, p.basename(child.path)));
      }
    case FileSystemEntityType.notFound:
      throw FileSystemException('does not exist', from);
    default:
      File(from).copySync(to);
  }
}
