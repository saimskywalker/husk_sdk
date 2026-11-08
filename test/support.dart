import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:husk_sdk/husk_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A temporary directory deleted after the current test.
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('husk_sdk_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

/// Writes [content] to [relative] under [root], creating directories.
File write(String root, String relative, String content) {
  final file = File(p.joinAll([root, ...relative.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file;
}

/// Reads [relative] under [root].
String read(String root, String relative) =>
    File(p.joinAll([root, ...relative.split('/')])).readAsStringSync();

/// Whether [relative] exists under [root].
bool exists(String root, String relative) =>
    FileSystemEntity.typeSync(p.joinAll([root, ...relative.split('/')])) !=
    FileSystemEntityType.notFound;

/// The `husk.yaml` used by most tests.
const String acmeSpec = '''
sdk:
  name: AcmeWidgetSDK
  version: 3.2.0
ios:
android:
  aar: 'acme-widget-*.aar'
''';

/// Creates a plugin shaped like `flutter create --template=plugin` output
/// (only the files husk_sdk reads or edits) and returns its root.
String fakePlugin({String spec = acmeSpec, bool groovy = false}) {
  final root = tempDir().path;
  write(root, 'pubspec.yaml', 'name: acme_widget\n');
  write(root, 'husk.yaml', spec);
  write(root, 'ios/acme_widget/Package.swift', '''
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "acme_widget",
    platforms: [.iOS("13.0")],
    products: [.library(name: "acme-widget", targets: ["acme_widget"])],
    targets: [
        .target(
            name: "acme_widget",
            dependencies: []
        )
    ]
)
''');
  write(root, 'ios/acme_widget/Sources/acme_widget/AcmeWidgetPlugin.swift', '''
import Flutter
public class AcmeWidgetPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    AcmeWidgetSDKHuskChannel.register(with: registrar)
  }
}
''');
  write(root, 'ios/acme_widget.podspec', '''
Pod::Spec.new do |s|
  s.name             = 'acme_widget'
  s.version          = '0.0.1'
  s.source_files = 'acme_widget/Sources/acme_widget/**/*'
  s.dependency 'Flutter'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
''');
  if (groovy) {
    write(root, 'android/build.gradle', '''
apply plugin: 'com.android.library'
android {
    namespace 'com.example.acme_widget'
}
''');
  } else {
    write(root, 'android/build.gradle.kts', '''
plugins {
    id("com.android.library")
}
android {
    namespace = "com.example.acme_widget"
}
''');
  }
  write(
    root,
    'android/src/main/kotlin/com/example/acme_widget/AcmeWidgetPlugin.kt',
    '''
package com.example.acme_widget
class AcmeWidgetPlugin {
    fun onAttachedToEngine(m: Any) { AcmeWidgetSDKHuskChannel.attach(m) }
}
''',
  );
  return root;
}

/// The `husk.yaml` of a native app, used by the native mode tests.
const String nativeSpec = '''
mode: native
sdk:
  name: AcmeWidgetSDK
  version: 3.2.0
ios:
android:
  aar: 'acme-widget-*.aar'
''';

/// Creates a plain iOS and Android app without Flutter (only the files
/// husk_sdk reads or edits) and returns its root.
String fakeNativeApp({String spec = nativeSpec}) {
  final root = tempDir().path;
  write(root, 'husk.yaml', spec);
  Directory(p.join(root, 'ios')).createSync();
  write(root, 'android/app/build.gradle.kts', '''
plugins {
    id("com.android.application")
}
android {
    namespace = "com.example.native_app"
}
''');
  return root;
}

/// Runs the CLI in-process and captures its output.
class CliRun {
  /// Runs `husk_sdk` with [args] against [project].
  CliRun(
    String project,
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    exitCode = runCli(
      ['-C', project, ...args],
      out: _out,
      err: _err,
      environment: environment,
    );
  }

  final _out = StringBuffer();
  final _err = StringBuffer();

  /// Exit code returned by the CLI.
  late final int exitCode;

  /// Captured stdout.
  String get out => _out.toString();

  /// Captured stderr.
  String get err => _err.toString();

  @override
  String toString() => 'exit $exitCode\n--- out\n$out--- err\n$err';
}

/// An XML `Info.plist` for an xcframework with the given slices
/// (`(identifier, variant or null, archs)`).
String xcframeworkPlist(List<(String, String?, List<String>)> slices) {
  final b = StringBuffer('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>
''');
  for (final (id, variant, archs) in slices) {
    b.write('''
    <dict>
      <key>LibraryIdentifier</key><string>$id</string>
      <key>LibraryPath</key><string>AcmeWidgetSDK.framework</string>
      <key>SupportedArchitectures</key>
      <array>${archs.map((a) => '<string>$a</string>').join()}</array>
      <key>SupportedPlatform</key><string>ios</string>
      ${variant == null ? '' : '<key>SupportedPlatformVariant</key><string>$variant</string>'}
    </dict>
''');
  }
  b.write('''
  </array>
  <key>CFBundlePackageType</key><string>XFWK</string>
  <key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict>
</plist>
''');
  return b.toString();
}

/// Bytes that start like a static archive.
final Uint8List staticBinary = Uint8List.fromList([
  ...'!<arch>\n'.codeUnits,
  ...List.filled(64, 0),
]);

/// Bytes that start like a 64-bit little-endian Mach-O dylib.
final Uint8List dynamicBinary = () {
  final b = ByteData(64)
    ..setUint32(0, 0xfeedfacf, Endian.little)
    ..setUint32(4, 0x0100000c, Endian.little)
    ..setUint32(12, 6, Endian.little);
  return b.buffer.asUint8List();
}();

/// Builds a fake xcframework at [path]. By default it has a device and a
/// simulator slice, both static, version 3.2.0.
void fakeXcframework(
  String path, {
  List<(String, String?, List<String>)> slices = const [
    ('ios-arm64', null, ['arm64']),
    ('ios-arm64_x86_64-simulator', 'simulator', ['arm64', 'x86_64']),
  ],
  String version = '3.2.0',
  bool dynamic = false,
}) {
  write(path, 'Info.plist', xcframeworkPlist(slices));
  for (final (id, _, _) in slices) {
    write(path, '$id/AcmeWidgetSDK.framework/Info.plist', '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>$version</string>
</dict></plist>
''');
    File(
      p.join(path, id, 'AcmeWidgetSDK.framework', 'AcmeWidgetSDK'),
    ).writeAsBytesSync(dynamic ? dynamicBinary : staticBinary);
  }
}

/// Builds a fake AAR at [path].
void fakeAar(
  String path, {
  bool manifest = true,
  bool classes = true,
  String? versionName,
  List<String> abis = const [],
}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile.bytes(name, bytes));
  if (manifest) {
    add(
      'AndroidManifest.xml',
      '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.acme.widget"${versionName == null ? '' : ' android:versionName="$versionName"'}>
    <uses-sdk android:minSdkVersion="21" />
</manifest>
'''
          .codeUnits,
    );
  }
  add('R.txt', const []);
  if (classes) {
    add('classes.jar', [0x50, 0x4b, 0x05, 0x06, ...List.filled(18, 0)]);
  }
  for (final abi in abis) {
    add('jni/$abi/libacme.so', [0x7f, 0x45, 0x4c, 0x46]);
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(ZipEncoder().encode(archive));
}
