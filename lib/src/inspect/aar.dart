import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../report.dart';

/// What `doctor` and `check` know about an AAR.
class AarInfo {
  /// Creates the result of [inspectAar].
  AarInfo({
    required this.path,
    required this.findings,
    this.manifestPackage,
    this.versionName,
    this.minSdk,
    this.hasClasses = false,
    this.abis = const [],
    this.fileVersion,
  });

  /// Absolute path of the `.aar` file.
  final String path;

  /// Problems found while reading it.
  final List<Finding> findings;

  /// `package` attribute of its `AndroidManifest.xml`.
  final String? manifestPackage;

  /// `android:versionName` of its manifest, which many libraries omit.
  final String? versionName;

  /// `android:minSdkVersion` of its manifest.
  final String? minSdk;

  /// Whether it contains `classes.jar`.
  final bool hasClasses;

  /// ABIs with native libraries under `jni/`.
  final List<String> abis;

  /// Version parsed from the file name, e.g. `3.2.0` from `x-3.2.0.aar`.
  final String? fileVersion;

  /// Best guess at the library version.
  String? get version => versionName ?? fileVersion;
}

final _fileVersion = RegExp(r'[-_]v?(\d+(?:\.\d+)+(?:[-+][\w.]+)?)\.aar$');
final _jniLibrary = RegExp(r'^jni/([^/]+)/[^/]+\.so$');

/// Reads the AAR at [path] without extracting it. Never throws for bad
/// input; problems are reported as findings.
AarInfo inspectAar(String path) {
  final findings = <Finding>[];
  void add(Level level, String message) =>
      findings.add(Finding(level, message));
  final fileVersion = _fileVersion.firstMatch(p.basename(path))?.group(1);
  InputFileStream? input;
  Archive? archive;
  try {
    input = InputFileStream(path);
    archive = ZipDecoder().decodeStream(input);
    if (archive.files.isEmpty) {
      add(Level.error, 'empty, or not a zip archive (AAR)');
      return AarInfo(path: path, findings: findings, fileVersion: fileVersion);
    }
    String? package, versionName, minSdk;
    var hasClasses = false;
    final abis = <String>{};
    for (final entry in archive.files.where((e) => e.isFile)) {
      final name = entry.name.replaceAll(r'\', '/');
      if (name == 'classes.jar') hasClasses = true;
      if (_jniLibrary.firstMatch(name) case final jni?) abis.add(jni[1]!);
      if (name != 'AndroidManifest.xml') continue;
      if (entry.size > 4 * 1024 * 1024) {
        add(Level.error, 'AndroidManifest.xml is implausibly large');
        continue;
      }
      try {
        final xml = XmlDocument.parse(utf8.decode(entry.content));
        final manifest = xml.rootElement;
        package = manifest.getAttribute('package');
        versionName = _androidAttribute(manifest, 'versionName');
        final usesSdk = manifest.findElements('uses-sdk').firstOrNull;
        minSdk = usesSdk == null
            ? null
            : _androidAttribute(usesSdk, 'minSdkVersion');
      } on FormatException catch (e) {
        add(Level.error, 'AndroidManifest.xml: ${e.message}');
      } on XmlException catch (e) {
        add(Level.error, 'AndroidManifest.xml: ${e.message}');
      }
    }
    if (!archive.files.any((f) => f.name == 'AndroidManifest.xml')) {
      add(
        Level.error,
        'no AndroidManifest.xml inside: not an Android library (AAR)',
      );
    }
    if (!hasClasses) {
      add(Level.warning, 'no classes.jar inside: the AAR carries no code');
    }
    return AarInfo(
      path: path,
      findings: findings,
      manifestPackage: package,
      versionName: versionName,
      minSdk: minSdk,
      hasClasses: hasClasses,
      abis: abis.toList()..sort(),
      fileVersion: fileVersion,
    );
  } on Object catch (e) {
    // The zip reader throws a mix of exception types for corrupt input.
    add(Level.error, 'cannot read as a zip archive: $e');
    return AarInfo(path: path, findings: findings, fileVersion: fileVersion);
  } finally {
    archive?.clearSync();
    input?.closeSync();
  }
}

const _androidNs = 'http://schemas.android.com/apk/res/android';

String? _androidAttribute(XmlElement element, String local) => element
    .attributes
    .where(
      (a) =>
          a.name.local == local &&
          (a.name.namespaceUri == _androidNs || a.name.prefix == 'android'),
    )
    .firstOrNull
    ?.value;
