import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'names.dart';

/// Default spec file name, looked up in the project directory.
const String specFileName = 'husk.yaml';

/// Thrown when `husk.yaml` is missing, malformed or inconsistent.
class SpecException implements Exception {
  /// Creates an exception with a message that names the offending key.
  SpecException(this.message);

  /// Human readable description, prefixed with the key path when known.
  final String message;

  @override
  String toString() => message;
}

/// The parsed and validated contents of `husk.yaml`.
///
/// Every path is stored in POSIX form relative to [root]; use [resolve] to
/// turn one into a native absolute path.
class HuskSpec {
  /// Creates a spec. Use [HuskSpec.load] or [HuskSpec.parse] instead.
  HuskSpec({
    required this.root,
    required this.sdkName,
    required this.version,
    required this.plugin,
    required this.shim,
    required this.channel,
    required this.envVar,
    required this.gradleProperty,
    required this.ios,
    required this.android,
    required this.dart,
    this.isNative = false,
  });

  /// Reads and validates `husk.yaml` from [projectDir].
  factory HuskSpec.load(String projectDir, {String? specPath}) {
    final file = File(specPath ?? p.join(projectDir, specFileName));
    if (!file.existsSync()) {
      throw SpecException(
        'No ${p.basename(file.path)} in ${p.normalize(p.absolute(projectDir))}. '
        'Run `dart run husk_sdk init --sdk <Name>` to create one.',
      );
    }
    return HuskSpec.parse(
      file.readAsStringSync(),
      root: p.normalize(p.absolute(projectDir)),
      sourceName: file.path,
    );
  }

  /// Parses [yamlText] as a spec for the project at [root].
  ///
  /// Defaults that depend on the project (plugin name, Kotlin package) are
  /// read from `pubspec.yaml` and the Gradle build file under [root].
  factory HuskSpec.parse(
    String yamlText, {
    required String root,
    String sourceName = specFileName,
  }) {
    final Object? doc;
    try {
      doc = loadYaml(yamlText, sourceUrl: Uri.file(sourceName));
    } on YamlException catch (e) {
      throw SpecException(
        '$specFileName: ${e.message} (${e.span?.start.line})',
      );
    }
    // Native mode wires a plain iOS or Android app: there is no Flutter
    // plugin, so no pubspec, method channel or Dart class.
    final native = doc is YamlMap && doc['mode'] == 'native';
    final top = _Node(doc, '').map(
      native
          ? 'mode sdk shim binary ios android'
          : 'mode sdk plugin shim channel binary ios android dart',
    );
    top.child('mode').optionalString(modePattern);
    final sdk = top.child('sdk').map('name version');
    final sdkName = sdk.child('name').requiredString(identifier);
    final version = sdk.child('version').optionalString(versionPattern);
    final words = splitWords(sdkName);
    final plugin = native
        ? null
        : top.child('plugin').optionalString(dartPackageName) ??
              _pubspecName(root) ??
              (throw SpecException(
                '$specFileName: plugin: not set and no pubspec.yaml name to default to',
              ));
    final shim =
        top.child('shim').optionalString(identifier) ?? '${sdkName}Husk';
    // In native mode the shim's Swift package stands in for the plugin.
    final name = plugin ?? shim;
    final channel =
        top.child('channel').optionalString(channelPattern) ?? '$name/husk';
    final binary = top.child('binary').mapOrEmpty('env gradle_property');
    final envVar =
        binary.child('env').optionalString(identifier) ??
        '${screamingSnake(words)}_DIR';
    final gradleProperty =
        binary.child('gradle_property').optionalString(gradlePropertyPattern) ??
        '${lowerCamel(words)}Dir';
    final iosNode = top.child('ios');
    final ios = iosNode.isPresent
        ? _ios(iosNode, root, sdkName, name, native: native)
        : null;
    final androidNode = top.child('android');
    final android = androidNode.isPresent
        ? _android(androidNode, root, words, native: native)
        : null;
    if (ios == null && android == null) {
      throw SpecException(
        '$specFileName: configure at least one of `ios:` or `android:`',
      );
    }
    final dart = top.child('dart').mapOrEmpty('output class');
    final output =
        dart.child('output').optionalPath() ??
        'lib/src/${snake(words)}_husk.g.dart';
    final className =
        dart.child('class').optionalString(identifier) ??
        '${upperCamel(words)}Husk';
    if (!output.endsWith('.dart')) {
      throw SpecException('$specFileName: dart.output: must end in .dart');
    }
    return HuskSpec(
      root: root,
      sdkName: sdkName,
      version: version,
      plugin: name,
      shim: shim,
      channel: channel,
      envVar: envVar,
      gradleProperty: gradleProperty,
      ios: ios,
      android: android,
      dart: DartSpec(output: output, className: className),
      isNative: native,
    );
  }

  /// Absolute, normalized project directory (where `husk.yaml` lives).
  final String root;

  /// Swift module name of the vendor SDK, for example `AcmeWidgetSDK`.
  final String sdkName;

  /// Vendor SDK version the project expects, if pinned.
  final String? version;

  /// Name of the Flutter plugin (pubspec name); in native mode, the name of
  /// the generated Swift package, which is [shim].
  final String plugin;

  /// Name of the generated shim type and SwiftPM target.
  final String shim;

  /// Method channel the generated Dart and native code talk over.
  final String channel;

  /// Environment variable naming a directory that holds the vendor binaries.
  final String envVar;

  /// Gradle property naming a directory that holds the vendor AAR.
  final String gradleProperty;

  /// iOS settings, or null when iOS is not configured.
  final IosSpec? ios;

  /// Android settings, or null when Android is not configured.
  final AndroidSpec? android;

  /// Generated Dart API settings.
  final DartSpec dart;

  /// Whether this is `mode: native`: a plain iOS or Android app without
  /// Flutter. Native mode generates a standalone Swift package and
  /// `husk.gradle` but no method channel and no Dart class.
  final bool isNative;

  /// Compilation condition defined when the vendor SDK is linked.
  String get defineName => 'HUSK_${sdkName.toUpperCase()}';

  /// Native absolute path for a POSIX path relative to [root].
  String resolve(String posixRelative) =>
      p.normalize(p.join(root, p.joinAll(p.posix.split(posixRelative))));
}

/// iOS part of the spec.
class IosSpec {
  /// Creates the iOS settings.
  IosSpec({
    required this.xcframework,
    required this.packageDir,
    required this.podspec,
    required this.target,
  });

  /// File name of the vendor xcframework, e.g. `AcmeWidgetSDK.xcframework`.
  final String xcframework;

  /// Directory holding the plugin's `Package.swift`, relative to the root.
  final String packageDir;

  /// Podspec path relative to the root, or null to skip CocoaPods.
  final String? podspec;

  /// Name of the plugin's own SwiftPM target.
  final String target;

  /// Git-ignored directory inside the package where `link` puts the binary.
  String get dropDir => '$packageDir/$dropDirName';

  /// `Package.swift` path relative to the root.
  String get manifest => '$packageDir/Package.swift';
}

/// Android part of the spec.
class AndroidSpec {
  /// Creates the Android settings.
  AndroidSpec({
    required this.aar,
    required this.maven,
    required this.moduleDir,
    required this.kotlinPackage,
    required this.sourceDir,
  });

  /// File name or glob of the vendor AAR, when the SDK ships as a file.
  final String? aar;

  /// Maven settings, when the SDK comes from a private repository.
  final MavenSpec? maven;

  /// Gradle module directory of the plugin, relative to the root.
  final String moduleDir;

  /// Kotlin package of the generated sources.
  final String kotlinPackage;

  /// Main Kotlin source directory, relative to [moduleDir].
  final String sourceDir;

  /// Git-ignored directory inside the module where `link` puts the AAR.
  String get dropDir => '$moduleDir/$dropDirName';
}

/// Private Maven repository settings for the Android SDK.
class MavenSpec {
  /// Creates the Maven settings.
  MavenSpec({
    required this.coordinates,
    required this.urlProperty,
    required this.urlEnv,
    required this.usernameProperty,
    required this.passwordProperty,
  });

  /// `group:artifact:version` of the vendor library.
  final String coordinates;

  /// Gradle property holding the repository URL.
  final String urlProperty;

  /// Environment variable holding the repository URL.
  final String urlEnv;

  /// Gradle property holding the repository user name, if it needs one.
  final String? usernameProperty;

  /// Gradle property holding the repository password, if it needs one.
  final String? passwordProperty;
}

/// Generated Dart API settings.
class DartSpec {
  /// Creates the Dart settings.
  DartSpec({required this.output, required this.className});

  /// Output file relative to the root.
  final String output;

  /// Name of the generated class.
  final String className;
}

// The platform parsers read keys in a fixed order, so the first error
// reported for a spec with several problems stays the same.
IosSpec _ios(
  _Node node,
  String root,
  String sdkName,
  String plugin, {
  required bool native,
}) {
  final n = node.mapOrEmpty(
    native
        ? 'xcframework package_dir'
        : 'xcframework package_dir podspec target',
  );
  final packageDir = n.child('package_dir').optionalPath() ?? 'ios/$plugin';
  final podspec = n.child('podspec');
  final skipPods =
      podspec.isPresent && (podspec.value == null || podspec.value == false);
  final defaultPodspec = File(p.join(root, 'ios', '$plugin.podspec'));
  return IosSpec(
    packageDir: packageDir,
    podspec: native || skipPods
        ? null
        : podspec.optionalPath() ??
              (defaultPodspec.existsSync() ? 'ios/$plugin.podspec' : null),
    xcframework:
        n.child('xcframework').optionalString(xcframeworkName) ??
        '$sdkName.xcframework',
    target: n.child('target').optionalString(identifier) ?? plugin,
  );
}

AndroidSpec _android(
  _Node node,
  String root,
  List<String> words, {
  required bool native,
}) {
  final n = node.mapOrEmpty(
    native
        ? 'aar maven module_dir package'
        : 'aar maven module_dir package source_dir',
  );
  final moduleDir =
      n.child('module_dir').optionalPath() ??
      (native ? 'android/app' : 'android');
  final m = n.child('maven');
  const mavenKeys =
      'coordinates url_property url_env username_property password_property';
  final maven = m.isPresent ? _maven(m.map(mavenKeys), words) : null;
  if (maven != null && n.child('aar').isPresent) {
    throw SpecException(
      '$specFileName: android: set either aar or maven, not both',
    );
  }
  return AndroidSpec(
    moduleDir: moduleDir,
    maven: maven,
    kotlinPackage:
        n.child('package').optionalString(kotlinPackagePattern) ??
        _gradleNamespace(p.join(root, p.joinAll(p.posix.split(moduleDir)))) ??
        (throw SpecException(
          '$specFileName: android.package: not set and no `namespace` '
          'found in $moduleDir/build.gradle(.kts)',
        )),
    aar: maven == null
        ? n.child('aar').optionalString(aarGlob) ?? '*.aar'
        : null,
    sourceDir: n.child('source_dir').optionalPath() ?? 'src/main/kotlin',
  );
}

MavenSpec _maven(_Node m, List<String> words) => MavenSpec(
  coordinates: m.child('coordinates').requiredString(mavenCoordinates),
  urlProperty:
      m.child('url_property').optionalString(gradlePropertyPattern) ??
      '${lowerCamel(words)}MavenUrl',
  urlEnv:
      m.child('url_env').optionalString(identifier) ??
      '${screamingSnake(words)}_MAVEN_URL',
  usernameProperty: m
      .child('username_property')
      .optionalString(gradlePropertyPattern),
  passwordProperty: m
      .child('password_property')
      .optionalString(gradlePropertyPattern),
);

String? _pubspecName(String root) {
  final file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    if (loadYaml(file.readAsStringSync()) case {
      'name': final String name,
    } when dartPackageName.hasMatch(name)) {
      return name;
    }
  } on YamlException {
    // No usable name: the caller asks for `plugin:`.
  }
  return null;
}

final _namespace = RegExp(
  r'''^\s*namespace\s*(?:=\s*)?["']([A-Za-z_][\w.]*)["']''',
  multiLine: true,
);

String? _gradleNamespace(String moduleDir) {
  for (final name in const ['build.gradle.kts', 'build.gradle']) {
    final file = File(p.join(moduleDir, name));
    if (file.existsSync()) {
      return _namespace.firstMatch(file.readAsStringSync())?.group(1);
    }
  }
  return null;
}

/// A YAML value plus the key path used in error messages (empty for the
/// top level).
class _Node {
  _Node(this.value, this.path, {this.isPresent = true});

  final Object? value;
  final String path;
  final bool isPresent;

  Never _fail(String message) => throw SpecException(
    '$specFileName: ${path.isEmpty ? specFileName : path}: $message',
  );

  /// Checks that this is a map whose keys are among the space-separated
  /// [allowed] names.
  _Node map(String allowed) {
    final v = value;
    if (v is! YamlMap) _fail(isPresent ? 'expected a map' : 'missing');
    final keys = allowed.split(' ')..sort();
    for (final key in v.keys) {
      if (key is! String || !keys.contains(key)) {
        throw SpecException(
          '$specFileName: ${path.isEmpty ? '' : '$path.'}$key: unknown key '
          '(allowed: ${keys.join(', ')})',
        );
      }
    }
    return this;
  }

  /// Like [map], but a missing, empty or `true` value is an empty map.
  _Node mapOrEmpty(String allowed) =>
      value == null || value == true ? _Node(YamlMap(), path) : map(allowed);

  _Node child(String key) {
    final map = value as YamlMap;
    return _Node(
      map[key],
      path.isEmpty ? key : '$path.$key',
      isPresent: map.containsKey(key),
    );
  }

  String requiredString(RegExp pattern) =>
      optionalString(pattern) ?? _fail('missing');

  String? optionalString(RegExp pattern) {
    final v = value;
    if (v == null) return null;
    final s = v is String ? v : (v is num ? '$v' : _fail('expected a string'));
    if (!pattern.hasMatch(s)) {
      _fail('"$s" is not valid here (expected ${describePattern(pattern)})');
    }
    return s;
  }

  String? optionalPath() {
    final v = value;
    if (v == null) return null;
    if (v is! String) _fail('expected a path');
    try {
      return normalizeRelative(v);
    } on FormatException catch (e) {
      _fail(e.message);
    }
  }
}
