import 'dart:io';

import 'package:path/path.dart' as p;

import 'spec.dart';

/// Builds the text of a starter `husk.yaml` for the project at [root].
///
/// Only the SDK name and the platforms are set; every other key is written
/// as a comment showing the default that applies, so the file documents
/// itself. Throws [SpecException] when a default cannot be worked out.
String initialSpec(
  String root, {
  required String sdkName,
  String? version,
  String? aar,
  String? androidPackage,
  bool? ios,
  bool? android,
  bool native = false,
}) {
  final withIos = ios ?? Directory(p.join(root, 'ios')).existsSync();
  final withAndroid =
      android ?? Directory(p.join(root, 'android')).existsSync();
  if (!withIos && !withAndroid) {
    throw SpecException(
      'no ios/ or android/ directory in $root; pass --ios or --android',
    );
  }
  final minimal = [
    if (native) 'mode: native',
    'sdk:',
    '  name: $sdkName',
    if (version != null) '  version: $version',
    if (withIos) 'ios:',
    if (withAndroid) 'android:',
    if (withAndroid && aar != null) "  aar: '$aar'",
    if (withAndroid && androidPackage != null) '  package: $androidPackage',
  ];
  // Parsing validates the inputs and computes every default.
  final spec = HuskSpec.parse('${minimal.join('\n')}\n', root: root);
  final iosSpec = spec.ios;
  final androidSpec = spec.android;
  final text = [
    '# husk.yaml: how husk_sdk wires the closed-source $sdkName into',
    '# this project. Paths are relative to this file. Commented-out',
    '# values show the defaults. Docs: https://pub.dev/packages/husk_sdk',
    if (native) ...[
      '# Native mode: a plain iOS/Android app, without Flutter.',
      'mode: native',
    ],
    'sdk:',
    '  name: $sdkName',
    version == null
        ? '  # version: 1.2.3  # check fails on a mismatch'
        : '  version: $version',
    '',
    if (!native) '# plugin: ${spec.plugin}',
    '# shim: ${spec.shim}',
    if (!native) '# channel: ${spec.channel}',
    '',
    '# Where `link` (and the Gradle build) look for the vendor files.',
    '# binary:',
    '#   env: ${spec.envVar}',
    '#   gradle_property: ${spec.gradleProperty}',
    if (iosSpec != null) ...[
      '',
      'ios:',
      '  # xcframework: ${iosSpec.xcframework}',
      '  # package_dir: ${iosSpec.packageDir}',
      if (!native) ...[
        "  # podspec: ${iosSpec.podspec ?? 'null  # no podspec found'}",
        '  # target: ${iosSpec.target}',
      ],
    ],
    if (androidSpec != null) ...[
      '',
      'android:',
      "  aar: '${aar ?? '*.aar'}'",
      '  # Or, for a private Maven repository instead of a file:',
      '  # maven:',
      '  #   coordinates: com.example:sdk:1.2.3',
      '  # module_dir: ${androidSpec.moduleDir}',
      androidPackage == null
          ? '  # package: ${androidSpec.kotlinPackage}'
          : '  package: $androidPackage',
      if (!native) '  # source_dir: ${androidSpec.sourceDir}',
    ],
    if (!native) ...[
      '',
      '# dart:',
      '#   output: ${spec.dart.output}',
      '#   class: ${spec.dart.className}',
    ],
    '',
  ].join('\n');
  // The written file must parse to the same spec.
  HuskSpec.parse(text, root: root);
  return text;
}
