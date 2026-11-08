import 'dart:io';

import 'package:path/path.dart' as p;

import 'inspect/aar.dart';
import 'inspect/macho.dart';
import 'inspect/xcframework.dart';
import 'locate.dart';
import 'names.dart';
import 'output.dart';
import 'report.dart';
import 'spec.dart';
import 'templates.dart';

/// Platforms `check --require-sdk` can insist on.
const List<String> platforms = ['ios', 'android'];

/// Builds the `doctor` / `check` report for [spec].
List<Section> diagnose(
  HuskSpec spec, {
  required Map<String, String> env,
  String? from,
  Set<String> requireSdk = const {},
}) => [
  if (spec.ios != null) _ios(spec, env, from, requireSdk),
  if (spec.android != null) _android(spec, env, from, requireSdk),
  _generated(spec),
  ?_git(spec),
];

/// The finding for a vendor binary that was not found.
Finding _notFound(
  HuskSpec spec,
  String platform,
  Map<String, String> env,
  String? from,
  Set<String> requireSdk, {
  required String dropDir,
  String also = '',
}) => Finding(
  requireSdk.contains(platform) ? Level.error : Level.info,
  'not found: builds use the ${spec.shim} stub',
  detail: [
    'looked in ${from != null ? '--from' : '\$${spec.envVar}'}'
        '${(from ?? env[spec.envVar]) == null ? ' (not set)' : ''}'
        ' and $dropDir/$also',
  ],
);

Section _ios(
  HuskSpec spec,
  Map<String, String> env,
  String? from,
  Set<String> requireSdk,
) {
  final ios = spec.ios!;
  final s = Section('iOS: ${ios.xcframework}');
  final found = locateXcframework(spec, env, from: from);
  if (found == null) {
    s.findings.add(
      _notFound(spec, 'ios', env, from, requireSdk, dropDir: ios.dropDir),
    );
  } else {
    final info = inspectXcframework(found.path);
    final version = info.version;
    final linkage = {for (final sl in info.slices) sl.linkage}
      ..remove(Linkage.unknown);
    s.add(
      Level.ok,
      'found via ${found.via}',
      detail: [
        displayPath(found.path, from: spec.root),
        'version ${version ?? 'unknown'}'
            '${linkage.length == 1 ? ', ${linkage.single.name}' : ''}',
        for (final sl in info.slices)
          '${sl.identifier.padRight(30)} ${sl.platformLabel.padRight(15)} '
              '${sl.architectures.join(' ')}',
      ],
    );
    s.findings.addAll(info.findings);
    if (ios.podspec != null && !found.via.startsWith(ios.dropDir)) {
      s.add(
        Level.info,
        'CocoaPods builds read only ${ios.dropDir}/; run '
        '`dart run husk_sdk link` to copy it there',
      );
    }
    _compareVersion(s, spec, version);
    if (linkage.contains(Linkage.dynamic)) {
      s.add(
        Level.info,
        'dynamic framework: SwiftPM and CocoaPods embed it; device builds '
        'need it signed',
      );
    }
  }
  final manifest = File(spec.resolve(ios.manifest));
  if (manifest.existsSync()) {
    final text = manifest.readAsStringSync();
    if (!text.contains('name: "${ios.target}"')) {
      s.add(
        Level.warning,
        '${ios.manifest} has no target named "${ios.target}"; set ios.target',
      );
    }
  } else if (ios.podspec == null) {
    s.add(Level.error, 'neither ${ios.manifest} nor a podspec exists');
  } else {
    s.add(Level.info, 'no ${ios.manifest}: CocoaPods only');
  }
  if (ios.podspec != null && !File(spec.resolve(ios.podspec!)).existsSync()) {
    s.add(Level.error, '${ios.podspec} does not exist');
  }
  _wiring(
    s,
    spec,
    dir: pluginSourceDir(spec),
    extensions: const ['.swift'],
    call: '${channelType(spec)}.register(with:',
    display: '${channelType(spec)}.register(with: registrar)',
    skip: '${channelType(spec)}.swift',
  );
  return s;
}

Section _android(
  HuskSpec spec,
  Map<String, String> env,
  String? from,
  Set<String> requireSdk,
) {
  final android = spec.android!;
  final maven = android.maven;
  final s = Section(
    'Android: ${maven == null ? android.aar : maven.coordinates}',
  );
  if (maven != null) {
    final url = env[maven.urlEnv];
    s.add(
      url == null && requireSdk.contains('android') ? Level.error : Level.info,
      url == null
          ? '\$${maven.urlEnv} not set: builds use the stub unless the Gradle '
                'property ${maven.urlProperty} is set'
          : 'repository from \$${maven.urlEnv}: $url',
    );
  } else {
    final found = locateAar(spec, env, from: from);
    if (found == null) {
      s.findings.add(
        _notFound(
          spec,
          'android',
          env,
          from,
          requireSdk,
          dropDir: android.dropDir,
          also: '; Gradle also reads the property ${spec.gradleProperty}',
        ),
      );
    } else {
      final (located, others) = found;
      final info = inspectAar(located.path);
      s.add(
        Level.ok,
        'found via ${located.via}',
        detail: [
          displayPath(located.path, from: spec.root),
          'version ${info.version ?? 'unknown'}'
              '${info.manifestPackage == null ? '' : ', package ${info.manifestPackage}'}'
              '${info.minSdk == null ? '' : ', minSdk ${info.minSdk}'}',
          if (info.abis.isNotEmpty) 'native code for ${info.abis.join(' ')}',
        ],
      );
      s.findings.addAll(info.findings);
      if (others.isNotEmpty) {
        s.add(
          Level.warning,
          '${others.length + 1} files match ${android.aar}; Gradle uses the '
          'last by name',
          detail: [for (final o in others) 'ignored ${p.basename(o)}'],
        );
      }
      _compareVersion(s, spec, info.version);
    }
  }
  final build = gradleBuildFile(spec);
  if (!File(spec.resolve(build)).existsSync()) {
    s.add(Level.error, '$build does not exist');
  }
  _wiring(
    s,
    spec,
    dir: '${android.moduleDir}/${android.sourceDir}',
    extensions: const ['.kt', '.java'],
    call: '${channelType(spec)}.attach(',
    display: '${channelType(spec)}.attach(binding.binaryMessenger)',
    skip: '${channelType(spec)}.kt',
  );
  return s;
}

void _compareVersion(Section s, HuskSpec spec, String? found) {
  final expected = spec.version;
  if (expected == null || found == null) return;
  if (found == expected) {
    s.add(Level.ok, 'version matches husk.yaml ($expected)');
  } else {
    s.add(
      Level.error,
      'version $found does not match sdk.version $expected in husk.yaml',
    );
  }
}

void _wiring(
  Section s,
  HuskSpec spec, {
  required String dir,
  required List<String> extensions,
  required String call,
  required String display,
  required String skip,
}) {
  final root = Directory(spec.resolve(dir));
  if (root.existsSync()) {
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File ||
          !extensions.contains(p.extension(e.path)) ||
          p.basename(e.path) == skip) {
        continue;
      }
      try {
        if (e.readAsStringSync().contains(call)) {
          s.add(
            Level.ok,
            'channel registered in ${displayPath(e.path, from: spec.root)}',
          );
          return;
        }
      } on FileSystemException {
        continue;
      }
    }
  }
  s.add(
    Level.error,
    'nothing calls $display under $dir/, so the Dart side always '
    'reports the SDK as unavailable',
  );
}

Section _generated(HuskSpec spec) {
  final s = Section('Generated files');
  const regenerate = '(run `dart run husk_sdk generate`)';
  for (final o in applyPlan(spec.root, planFiles(spec), dryRun: true)) {
    final (level, message) = switch (o.status) {
      FileStatus.unchanged => (Level.ok, 'up to date: ${o.path}'),
      FileStatus.created => (Level.error, 'missing: ${o.path} $regenerate'),
      FileStatus.updated => (Level.error, 'out of date: ${o.path} $regenerate'),
      FileStatus.failed => (Level.error, '${o.path}: ${o.message}'),
    };
    s.add(level, message);
  }
  return s;
}

/// Reports vendor binaries tracked by git. Returns null outside a git
/// work tree or without git.
Section? _git(HuskSpec spec) {
  final ProcessResult result;
  try {
    result = Process.runSync('git', [
      'ls-files',
      '-z',
      '--',
      '.',
    ], workingDirectory: spec.root);
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;
  final tracked = (result.stdout as String)
      .split('\x00')
      .where((f) => f.isNotEmpty);
  final aar = spec.android?.aar;
  final aarPattern = aar == null ? null : RegExp(globToRegExpSource(aar));
  final xcName = spec.ios?.xcframework;
  final hits = <String>{};
  for (final f in tracked) {
    final parts = f.split('/');
    if (parts.contains(dropDirName) && parts.length > 1) {
      hits.add(f);
    } else if (xcName != null && parts.contains(xcName)) {
      hits.add('${parts.sublist(0, parts.indexOf(xcName) + 1).join('/')}/');
    } else if (aarPattern != null && aarPattern.hasMatch(parts.last)) {
      hits.add(f);
    }
  }
  final s = Section('Git');
  if (hits.isEmpty) {
    s.add(Level.ok, 'no vendor binaries are tracked');
  } else {
    s.add(
      Level.error,
      'vendor binaries are tracked by git; remove them with `git rm --cached`',
      detail: hits.toList()..sort(),
    );
  }
  return s;
}
