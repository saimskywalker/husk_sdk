import 'package:husk_sdk/husk_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('native mode needs no pubspec and derives app-shaped defaults', () {
    final spec = HuskSpec.parse(nativeSpec, root: fakeNativeApp());
    expect(spec.isNative, isTrue);
    expect(spec.plugin, 'AcmeWidgetSDKHusk');
    expect(spec.ios!.packageDir, 'ios/AcmeWidgetSDKHusk');
    expect(spec.ios!.manifest, 'ios/AcmeWidgetSDKHusk/Package.swift');
    expect(spec.ios!.podspec, isNull);
    expect(spec.android!.moduleDir, 'android/app');
    expect(spec.android!.kotlinPackage, 'com.example.native_app');
    expect(spec.android!.dropDir, 'android/app/husk_vendor');
    expect(HuskSpec.parse(acmeSpec, root: fakePlugin()).isNative, isFalse);
  });

  test('native mode rejects the Flutter-only keys and unknown modes', () {
    final root = fakeNativeApp();
    for (final (yaml, key) in [
      ('plugin: x', 'plugin'),
      ('channel: x/husk', 'channel'),
      ('dart: {class: X}', 'dart'),
      ('ios: {podspec: x.podspec}', 'ios.podspec'),
      ('ios: {target: x}', 'ios.target'),
      ('android: {source_dir: src}', 'android.source_dir'),
    ]) {
      expect(
        () => HuskSpec.parse(
          'mode: native\nsdk: {name: AcmeWidgetSDK}\n$yaml\n',
          root: root,
        ),
        throwsA(
          isA<SpecException>().having(
            (e) => e.message,
            'message',
            contains('$key: unknown key'),
          ),
        ),
      );
    }
    expect(
      () => HuskSpec.parse('mode: app\nsdk: {name: X}\nios:\n', root: root),
      throwsA(isA<SpecException>()),
    );
  });

  test('generate writes a Swift package and husk.gradle, no Flutter glue', () {
    final root = fakeNativeApp();
    final run = CliRun(root, ['generate']);
    expect(run.exitCode, exitOk, reason: '$run');
    expect(run.out, isNot(contains('Wire the generated channel')));
    expect(run.out.trim().split('\n').skip(1).map((l) => l.trim().split(' ').last), [
      'ios/AcmeWidgetSDKHusk/Package.swift',
      'ios/AcmeWidgetSDKHusk/Sources/AcmeWidgetSDKHusk/AcmeWidgetSDKHusk.swift',
      'android/app/husk.gradle',
      'android/app/build.gradle.kts',
      'android/app/src/husk/linked/kotlin/com/example/native_app/AcmeWidgetSDKHusk.kt',
      'android/app/src/husk/stub/kotlin/com/example/native_app/AcmeWidgetSDKHusk.kt',
      '.gitignore',
    ]);

    final manifest = read(root, 'ios/AcmeWidgetSDKHusk/Package.swift');
    expect(manifest, startsWith('// swift-tools-version: 5.9\n'));
    expect(manifest, contains('// $generatedMarker'));
    expect(
      manifest,
      contains(
        'products: [.library(name: "AcmeWidgetSDKHusk", '
        'targets: ["AcmeWidgetSDKHusk"])]',
      ),
    );
    expect(
      manifest,
      contains('.binaryTarget(name: "AcmeWidgetSDK", path: path)'),
    );
    expect(manifest, contains('[.define("HUSK_ACMEWIDGETSDK")]'));
    expect(manifest, isNot(contains('for target in package.targets')));

    final gradle = read(root, 'android/app/husk.gradle');
    expect(gradle, contains('implementation files(huskAar)'));
    expect(gradle, contains('android.sourceSets.main.kotlin.srcDir('));
    expect(gradle, isNot(contains('flatDir')));
    expect(
      read(root, 'android/app/build.gradle.kts'),
      contains('apply(from = "husk.gradle")'),
    );

    final second = CliRun(root, ['generate']);
    expect(second.out, isNot(contains('created')));
    expect(second.out, isNot(contains('updated')));
  });

  test('check passes without a channel; link and unlink use the app dirs', () {
    final root = fakeNativeApp();
    CliRun(root, ['generate']);
    final check = CliRun(root, ['check']);
    expect(check.exitCode, exitOk, reason: '$check');
    expect(check.out, startsWith('husk_sdk check: AcmeWidgetSDK (native app)'));

    final vendor = tempDir().path;
    fakeXcframework(p.join(vendor, 'AcmeWidgetSDK.xcframework'));
    fakeAar(p.join(vendor, 'acme-widget-3.2.0.aar'));
    final link = CliRun(root, ['link', '--from', vendor]);
    expect(link.exitCode, exitOk, reason: '$link');
    expect(link.out, contains('-> ios/AcmeWidgetSDKHusk/husk_vendor/'));
    expect(link.out, contains('-> android/app/husk_vendor/'));
    expect(link.out, isNot(contains('pod install')));
    final linked = CliRun(root, [
      'check',
      '--require-sdk',
      'ios',
      '--require-sdk',
      'android',
    ]);
    expect(linked.exitCode, exitOk, reason: '$linked');
    expect(CliRun(root, ['unlink']).out, contains('removed'));
  });

  test('a Maven SDK keeps its repository wiring in native mode', () {
    final root = fakeNativeApp(
      spec: '''
mode: native
sdk: {name: AcmeWidgetSDK}
android:
  maven: {coordinates: "com.acme:widget:3.2.0"}
''',
    );
    expect(CliRun(root, ['generate']).exitCode, exitOk);
    final gradle = read(root, 'android/app/husk.gradle');
    expect(gradle, contains("implementation 'com.acme:widget:3.2.0'"));
    expect(gradle, contains('android.sourceSets.main.kotlin.srcDir('));
  });

  test('init --native writes a native spec without Flutter keys', () {
    final root = fakeNativeApp();
    final run = CliRun(root, [
      'init',
      '--native',
      '--force',
      '--sdk',
      'AcmeWidgetSDK',
      '--aar',
      'acme-widget-*.aar',
    ]);
    expect(run.exitCode, exitOk, reason: '$run');
    final text = read(root, 'husk.yaml');
    expect(text, contains('\nmode: native\n'));
    expect(text, contains('# module_dir: android/app'));
    for (final key in ['plugin:', 'channel:', 'dart:', 'podspec:', 'target:']) {
      expect(text, isNot(contains(key)), reason: key);
    }
    expect(HuskSpec.load(root).isNative, isTrue);
  });
}
