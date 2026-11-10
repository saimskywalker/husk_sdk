import 'dart:io';

import 'package:path/path.dart' as p;

import '../report.dart';
import 'macho.dart';
import 'plist.dart';

/// One library inside an xcframework (`AvailableLibraries` entry).
class XcSlice {
  /// Creates a slice description.
  XcSlice({
    required this.identifier,
    required this.platform,
    required this.variant,
    required this.architectures,
    required this.libraryPath,
    required this.linkage,
    required this.version,
  });

  /// Directory name inside the xcframework, e.g. `ios-arm64`.
  final String identifier;

  /// `SupportedPlatform`, e.g. `ios`.
  final String platform;

  /// `SupportedPlatformVariant`, e.g. `simulator`, or null for devices.
  final String? variant;

  /// `SupportedArchitectures`.
  final List<String> architectures;

  /// `LibraryPath`, e.g. `AcmeWidgetSDK.framework`.
  final String libraryPath;

  /// Whether the binary is a static archive or a dynamic library.
  final Linkage linkage;

  /// `CFBundleShortVersionString` of the framework, when it has one.
  final String? version;

  /// `ios`, `ios simulator`, `ios maccatalyst` ...
  String get platformLabel => variant == null ? platform : '$platform $variant';
}

/// What `doctor` and `check` know about an xcframework.
class XcframeworkInfo {
  /// Creates the result of [inspectXcframework].
  XcframeworkInfo(this.path, this.slices, this.findings);

  /// Absolute path of the `.xcframework` directory.
  final String path;

  /// Libraries listed in its `Info.plist`.
  final List<XcSlice> slices;

  /// Problems found while reading it.
  final List<Finding> findings;

  /// The version shared by all slices, or null when unknown or mixed.
  String? get version {
    final versions = {for (final s in slices) s.version}..remove(null);
    return versions.length == 1 ? versions.single : null;
  }
}

/// Reads an xcframework's `Info.plist` and each slice's framework
/// `Info.plist` and binary header. Never throws for bad input; problems are
/// reported as findings.
XcframeworkInfo inspectXcframework(String path) {
  final findings = <Finding>[];
  final slices = <XcSlice>[];
  final name = p.basename(path);
  void error(String m) => findings.add(Finding(Level.error, m));
  void warn(String m) => findings.add(Finding(Level.warning, m));
  XcframeworkInfo done() => XcframeworkInfo(path, slices, findings);

  final Object? plist;
  try {
    plist = parsePlist(File(p.join(path, 'Info.plist')).readAsBytesSync());
  } on FileSystemException {
    error('$name has no readable Info.plist');
    return done();
  } on FormatException catch (e) {
    error('$name/Info.plist: ${e.message}');
    return done();
  }
  final libraries = plist is Map ? plist['AvailableLibraries'] : null;
  if (libraries is! List || libraries.isEmpty) {
    error('$name/Info.plist lists no AvailableLibraries');
    return done();
  }

  for (final entry in libraries.whereType<Map<Object?, Object?>>()) {
    if (entry case {
      'LibraryIdentifier': final String id,
      'LibraryPath': final String libraryPath,
      'SupportedPlatform': final String platform,
    }) {
      if (_unsafe(id) || _unsafe(libraryPath)) {
        error('slice "$id" has a path that leaves the xcframework');
        continue;
      }
      final libraryDir = p.join(path, id, libraryPath);
      if (FileSystemEntity.typeSync(libraryDir) ==
          FileSystemEntityType.notFound) {
        error('slice $id is listed but $id/$libraryPath is missing');
        continue;
      }
      String? version;
      var binaryPath = entry['BinaryPath'];
      if (libraryPath.endsWith('.framework')) {
        final info = [
          p.join(libraryDir, 'Info.plist'),
          p.join(libraryDir, 'Resources', 'Info.plist'),
          p.join(libraryDir, 'Versions', 'Current', 'Resources', 'Info.plist'),
        ].map(File.new).where((f) => f.existsSync()).firstOrNull;
        if (info != null) {
          try {
            if (parsePlist(info.readAsBytesSync()) case {
              'CFBundleShortVersionString': final String v,
            }) {
              version = v;
            }
          } on FormatException catch (e) {
            warn('$id/$libraryPath Info.plist: ${e.message}');
          }
        }
        binaryPath ??= p.join(
          libraryPath,
          p.basenameWithoutExtension(libraryPath),
        );
      } else {
        binaryPath ??= libraryPath;
      }
      var linkage = Linkage.unknown;
      if (binaryPath is String && !_unsafe(binaryPath)) {
        final binary = File(p.join(path, id, binaryPath));
        if (binary.existsSync()) {
          linkage = detectLinkage(binary);
        } else {
          error('slice $id: binary $binaryPath is missing');
        }
      }
      final variant = entry['SupportedPlatformVariant'];
      final archs = entry['SupportedArchitectures'];
      slices.add(
        XcSlice(
          identifier: id,
          platform: platform,
          variant: variant is String ? variant : null,
          architectures: archs is List
              ? [for (final a in archs) '$a']
              : const [],
          libraryPath: libraryPath,
          linkage: linkage,
          version: version,
        ),
      );
    } else {
      error(
        'an AvailableLibraries entry lacks LibraryIdentifier, '
        'LibraryPath or SupportedPlatform',
      );
    }
  }

  final ios = slices.where((s) => s.platform == 'ios');
  final simulator = ios.where((s) => s.variant == 'simulator');
  if (!ios.any((s) => s.variant == null)) {
    error('no iOS device slice (ios, arm64): device builds cannot link it');
  }
  if (simulator.isEmpty) {
    error('no iOS simulator slice: simulator builds and CI cannot link it');
  } else if (!simulator.any((s) => s.architectures.contains('arm64'))) {
    warn(
      'the iOS simulator slice has no arm64: Apple silicon Macs must '
      'build for x86_64 under Rosetta',
    );
  }
  final versions = {for (final s in slices) s.version}..remove(null);
  if (versions.length > 1) {
    warn('slices report different versions: ${versions.join(', ')}');
  }
  final linkages = {for (final s in slices) s.linkage}..remove(Linkage.unknown);
  if (linkages.length > 1) warn('some slices are static and some dynamic');
  return done();
}

bool _unsafe(String relative) =>
    p.isAbsolute(relative) || p.split(relative).contains('..');
