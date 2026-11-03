import 'dart:convert';
import 'dart:io';

import 'package:husk_sdk/husk_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

void main() {
  test('--version matches pubspec.yaml and CHANGELOG.md', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(packageVersion, pubspec['version']);
    expect(
      File('CHANGELOG.md').readAsStringSync(),
      contains('## $packageVersion'),
    );
    final out = StringBuffer();
    expect(runCli(['--version'], out: out), exitOk);
    expect(out.toString().trim(), 'husk_sdk $packageVersion');
  });

  test('usage errors exit 2', () {
    final root = fakePlugin();
    expect(CliRun(root, []).exitCode, exitUsage);
    expect(CliRun(root, ['nope']).exitCode, exitUsage);
    expect(CliRun(root, ['check', '--require-sdk', 'web']).exitCode, exitUsage);
    expect(CliRun(root, ['init']).exitCode, exitUsage);
  });

  test('a missing or invalid husk.yaml exits 2', () {
    final empty = tempDir().path;
    final missing = CliRun(empty, ['check']);
    expect(missing.exitCode, exitUsage);
    expect(missing.err, contains('husk_sdk init'));
    final root = fakePlugin(
      spec: 'sdk: {name: AcmeWidgetSDK}\nios: {bogus: 1}\n',
    );
    expect(CliRun(root, ['check']).exitCode, exitUsage);
  });

  test('subcommand --help', () {
    final run = CliRun(fakePlugin(), ['check', '--help']);
    expect(run.exitCode, exitOk);
    expect(run.out, contains('--require-sdk'));
    expect(run.out, contains('--json'));
  });

  test('init writes a spec that parses and documents the defaults', () {
    final root = fakePlugin();
    File(p.join(root, 'husk.yaml')).deleteSync();
    final run = CliRun(root, [
      'init',
      '--sdk',
      'AcmeWidgetSDK',
      '--sdk-version',
      '3.2.0',
      '--aar',
      'acme-widget-*.aar',
    ]);
    expect(run.exitCode, exitOk, reason: '$run');
    final text = read(root, 'husk.yaml');
    expect(text, contains('#   env: ACME_WIDGET_SDK_DIR'));
    expect(text, contains('# package: com.example.acme_widget'));
    final spec = HuskSpec.load(root);
    expect(spec.android!.aar, 'acme-widget-*.aar');
    expect(CliRun(root, ['init', '--sdk', 'X']).exitCode, exitProblems);
  });

  group('check', () {
    test('passes on a generated project without binaries', () {
      final root = fakePlugin();
      CliRun(root, ['generate']);
      final run = CliRun(root, ['check']);
      expect(run.exitCode, exitOk, reason: '$run');
    });

    test('fails when generated files are stale or missing', () {
      final root = fakePlugin();
      final run = CliRun(root, ['check']);
      expect(run.exitCode, exitProblems);
      expect(run.out, contains('missing: android/husk.gradle'));
      CliRun(root, ['generate']);
      write(root, 'husk.yaml', acmeSpec.replaceFirst('3.2.0', '3.3.0'));
      expect(CliRun(root, ['check']).out, contains('out of date: lib/src/'));
    });

    test('fails when the plugin never registers the channel', () {
      final root = fakePlugin();
      write(
        root,
        'ios/acme_widget/Sources/acme_widget/AcmeWidgetPlugin.swift',
        '// nothing\n',
      );
      CliRun(root, ['generate']);
      final run = CliRun(root, ['check']);
      expect(run.exitCode, exitProblems);
      expect(run.out, contains('AcmeWidgetSDKHuskChannel.register(with:'));
    });

    test('--require-sdk fails until the binary is there', () {
      final root = fakePlugin();
      CliRun(root, ['generate']);
      expect(
        CliRun(root, ['check', '--require-sdk', 'ios']).exitCode,
        exitProblems,
      );
      fakeXcframework(
        p.join(root, 'ios/acme_widget/husk_vendor/AcmeWidgetSDK.xcframework'),
      );
      expect(CliRun(root, ['check', '--require-sdk', 'ios']).exitCode, exitOk);
      expect(
        CliRun(root, [
          'check',
          '--require-sdk',
          'ios',
          '--require-sdk',
          'android',
        ]).exitCode,
        exitProblems,
      );
    });

    test('fails on a version mismatch', () {
      final root = fakePlugin();
      CliRun(root, ['generate']);
      fakeAar(p.join(root, 'android/husk_vendor/acme-widget-3.1.0.aar'));
      final run = CliRun(root, ['check']);
      expect(run.exitCode, exitProblems);
      expect(run.out, contains('version 3.1.0 does not match'));
    });

    test('fails when a vendor binary is committed', () {
      final git = Process.runSync('git', ['--version']);
      if (git.exitCode != 0) return;
      final root = fakePlugin();
      CliRun(root, ['generate']);
      fakeAar(p.join(root, 'libs/acme-widget-3.2.0.aar'));
      Process.runSync('git', ['init', '-q'], workingDirectory: root);
      Process.runSync('git', ['add', '-A'], workingDirectory: root);
      final run = CliRun(root, ['check']);
      expect(run.exitCode, exitProblems, reason: '$run');
      expect(run.out, contains('libs/acme-widget-3.2.0.aar'));
    });

    test('--json prints sections, findings and the check exit code', () {
      final root = fakePlugin();
      final check = CliRun(root, ['check', '--json']);
      expect(check.exitCode, exitProblems, reason: '$check');
      expect(check.err, isEmpty);
      final checkJson = jsonDecode(check.out) as Map<String, dynamic>;
      expect(checkJson['exitCode'], exitProblems);
      final findings = [
        for (final section in checkJson['sections'] as List<dynamic>)
          for (final finding
              in (section as Map<String, dynamic>)['findings'] as List<dynamic>)
            finding as Map<String, dynamic>,
      ];
      expect(findings, isNotEmpty);
      expect(
        findings.map((f) => f['level']),
        everyElement(isIn(['warning', 'error'])),
      );
      expect(
        findings.map((f) => f['message']),
        contains(contains('missing: android/husk.gradle')),
      );
      expect(findings.first['detail'], isA<List<dynamic>>());

      final doctor = CliRun(root, ['doctor', '--json']);
      expect(doctor.exitCode, exitOk, reason: '$doctor');
      final doctorJson = jsonDecode(doctor.out) as Map<String, dynamic>;
      expect(doctorJson['exitCode'], exitProblems);
      final doctorLevels = [
        for (final section in doctorJson['sections'] as List<dynamic>)
          for (final finding
              in (section as Map<String, dynamic>)['findings'] as List<dynamic>)
            (finding as Map<String, dynamic>)['level'],
      ];
      expect(doctorLevels, contains('info'));
    });
  });

  group('link and unlink', () {
    test('copy from --from or the env variable, then remove', () {
      final root = fakePlugin();
      final vendor = tempDir().path;
      fakeXcframework(p.join(vendor, 'AcmeWidgetSDK.xcframework'));
      fakeAar(p.join(vendor, 'acme-widget-3.1.0.aar'));
      fakeAar(p.join(vendor, 'acme-widget-3.2.0.aar'));
      write(root, 'android/husk_vendor/acme-widget-3.0.0.aar', 'old');

      final run = CliRun(root, ['link', '--from', vendor]);
      expect(run.exitCode, exitOk, reason: '$run');
      expect(
        exists(
          root,
          'ios/acme_widget/husk_vendor/AcmeWidgetSDK.xcframework/Info.plist',
        ),
        isTrue,
      );
      expect(
        Directory(
          p.join(root, 'android/husk_vendor'),
        ).listSync().map((e) => p.basename(e.path)),
        ['acme-widget-3.2.0.aar'],
      );

      CliRun(root, ['generate']);
      final doctor = CliRun(root, ['doctor']);
      expect(doctor.out, contains('found via ios/acme_widget/husk_vendor/'));
      expect(doctor.out, contains('version 3.2.0, static'));

      expect(CliRun(root, ['unlink']).exitCode, exitOk);
      expect(exists(root, 'ios/acme_widget/husk_vendor'), isFalse);
      expect(exists(root, 'android/husk_vendor'), isFalse);

      final viaEnv = CliRun(
        root,
        ['link'],
        environment: {'ACME_WIDGET_SDK_DIR': vendor},
      );
      expect(viaEnv.exitCode, exitOk, reason: '$viaEnv');
    });

    test('--clear-swiftpm-cache deletes only the manifest cache', () {
      if (!Platform.isMacOS) return;
      final root = fakePlugin();
      final home = tempDir().path;
      final caches = p.join(home, 'Library/Caches/org.swift.swiftpm');
      write(caches, 'manifests/manifest.db', 'x');
      write(caches, 'other/keep', 'x');
      final run = CliRun(
        root,
        ['unlink', '--clear-swiftpm-cache'],
        environment: {'HOME': home},
      );
      expect(run.out, contains('Nothing to remove'));
      fakeXcframework(
        p.join(root, 'ios/acme_widget/husk_vendor/AcmeWidgetSDK.xcframework'),
      );
      final again = CliRun(
        root,
        ['unlink', '--clear-swiftpm-cache'],
        environment: {'HOME': home},
      );
      expect(again.out, contains('Cleared the Swift Package Manager'));
      expect(Directory(p.join(caches, 'manifests')).existsSync(), isFalse);
      expect(File(p.join(caches, 'other/keep')).existsSync(), isTrue);
    });

    test('nothing to copy exits 1', () {
      final root = fakePlugin();
      expect(
        CliRun(root, ['link', '--from', tempDir().path]).exitCode,
        exitProblems,
      );
    });

    test('symlinks and permission bits survive the copy', () {
      if (Platform.isWindows) return;
      final src = tempDir().path;
      write(src, 'Versions/A/Tool', '#!/bin/sh\n');
      Process.runSync('chmod', ['755', p.join(src, 'Versions/A/Tool')]);
      Link(p.join(src, 'Versions/Current')).createSync('A');
      final dst = p.join(tempDir().path, 'copy');
      copyTree(src, dst);
      expect(Link(p.join(dst, 'Versions/Current')).targetSync(), 'A');
      expect(
        File(p.join(dst, 'Versions/A/Tool')).statSync().modeString(),
        'rwxr-xr-x',
      );
    });
  });
}
