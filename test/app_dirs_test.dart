import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jingerpicmanager/data/app_dirs.dart';

void main() {
  group('resolveSupportDirectory', () {
    test('uses APPDATA when available', () {
      final dir = resolveSupportDirectory(
        environment: <String, String>{'APPDATA': r'C:\Users\me\AppData\Roaming'},
      );
      expect(dir.path,
          r'C:\Users\me\AppData\Roaming\jingerpicmanager');
    });

    test('falls back to LOCALAPPDATA', () {
      final dir = resolveSupportDirectory(
        environment: <String, String>{
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        },
      );
      expect(dir.path, r'C:\Users\me\AppData\Local\jingerpicmanager');
    });

    test('falls back to USERPROFILE/AppData/Roaming', () {
      final dir = resolveSupportDirectory(
        environment: <String, String>{'USERPROFILE': r'C:\Users\me'},
      );
      expect(dir.path, contains(r'C:\Users\me'));
      expect(
        dir.path,
        endsWith(p.join('AppData', 'Roaming', 'jingerpicmanager')),
      );
    });

    test('falls back to the temp directory', () {
      final dir = resolveSupportDirectory(environment: <String, String>{});
      expect(dir.path, endsWith('jingerpicmanager'));
      expect(dir.path.startsWith(Directory.systemTemp.path), isTrue);
    });

    test('ignores blank variables', () {
      final dir = resolveSupportDirectory(
        environment: <String, String>{
          'APPDATA': '   ',
          'LOCALAPPDATA': r'D:\AppData\Local',
        },
      );
      expect(dir.path, r'D:\AppData\Local\jingerpicmanager');
    });

    test('honours a custom folder name', () {
      final dir = resolveSupportDirectory(
        environment: <String, String>{'APPDATA': r'C:\Roaming'},
        folderName: 'custom',
      );
      expect(dir.path, r'C:\Roaming\custom');
    });

    test('real environment resolves to an absolute path', () {
      final dir = resolveSupportDirectory();
      expect(dir.isAbsolute, isTrue);
    });
  });
}
