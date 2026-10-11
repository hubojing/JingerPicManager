import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jingerpicmanager/app_info.dart';

/// Reads the `version:` entry from pubspec.yaml (the build number after `+`
/// is stripped, because AppInfo only tracks the marketing version).
String pubspecVersion() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    // Tests may run from a different working directory in some toolchains.
    final alt = File('${Directory.current.path}/pubspec.yaml');
    if (!alt.existsSync()) return '';
    return _parse(alt.readAsStringSync());
  }
  return _parse(file.readAsStringSync());
}

String _parse(String content) {
  for (final line in content.split('\n')) {
    final match = RegExp(r'^version:\s*(\S+)').firstMatch(line);
    if (match != null) return match.group(1)!.split('+').first;
  }
  return '';
}

void main() {
  group('AppInfo', () {
    test('version matches pubspec.yaml', () {
      expect(pubspecVersion(), isNotEmpty);
      expect(AppInfo.version, pubspecVersion());
    });

    test('version is a valid semver-like string', () {
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(AppInfo.version), isTrue);
    });

    test('tag version prefixes a v', () {
      expect(AppInfo.tagVersion, 'v${AppInfo.version}');
    });

    test('display name combines name and version', () {
      expect(AppInfo.displayName, 'JingerPicManager ${AppInfo.version}');
    });

    test('author identity is filled in', () {
      expect(AppInfo.authorName, '靖待jinger');
      expect(AppInfo.authorUrl, 'https://github.com/hubojing');
      expect(Uri.parse(AppInfo.authorUrl).isAbsolute, isTrue);
    });
  });

  group('externalOpenCommand', () {
    test('uses explorer with the raw url', () {
      final cmd = externalOpenCommand('https://github.com/hubojing');
      expect(cmd.length, 2);
      expect(cmd.first, 'explorer');
      expect(cmd.last, 'https://github.com/hubojing');
    });

    test('trims surrounding whitespace', () {
      final cmd = externalOpenCommand('  https://example.com  ');
      expect(cmd.last, 'https://example.com');
    });
  });
}
