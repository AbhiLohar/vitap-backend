import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitap_super_app/services/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('detects newer patch version', () {
      expect(UpdateService.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
    });

    test('detects newer minor version', () {
      expect(UpdateService.compareVersions('1.1.0', '1.0.9'), greaterThan(0));
    });

    test('detects newer major version', () {
      expect(UpdateService.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('handles leading v and whitespace', () {
      expect(UpdateService.compareVersions('v1.0.5', '1.0.4'), greaterThan(0));
      expect(UpdateService.compareVersions('  V2.1.0  ', '2.0.9'), greaterThan(0));
    });

    test('returns 0 for equal versions', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), equals(0));
      expect(UpdateService.compareVersions('v1.0.0', '1.0.0'), equals(0));
      expect(UpdateService.compareVersions('1.0.4', '1.0.4'), equals(0));
      expect(UpdateService.compareVersions('v1.0.4', '1.0.4'), equals(0));
      expect(UpdateService.compareVersions('1.0.4', '1.0.4+5'), equals(0));
      expect(UpdateService.compareVersions('1.0.4+5', '1.0.4'), equals(0));
    });

    test('no update when installed version is equal to or greater than available', () {
      // compareVersions(latest, current) > 0 means update available
      expect(UpdateService.compareVersions('1.0.4', '1.0.4') > 0, isFalse);
      expect(UpdateService.compareVersions('1.0.4', '1.0.5') > 0, isFalse);
      expect(UpdateService.compareVersions('1.0.4', '1.0.3') > 0, isTrue);
    });

    test('handles multi-digit semantic numbers correctly (1.10.0 > 1.9.0)', () {
      expect(UpdateService.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(UpdateService.compareVersions('1.2.0', '1.10.0'), lessThan(0));
    });

    test('handles build metadata (+1)', () {
      expect(UpdateService.compareVersions('1.0.1+2', '1.0.0+1'), greaterThan(0));
    });

    test('currentAppVersion and fallbackVersion are set to 1.0.6', () {
      expect(UpdateService.currentAppVersion, equals('1.0.6'));
      expect(UpdateService.fallbackVersion, equals('1.0.6'));
      expect(UpdateService.currentVersionCode, equals(7));
    });
  });

  group('UpdateService Multi-Tier URL & Parsing', () {
    test('CDN URL points to raw githubusercontent Fastly endpoint', () {
      expect(UpdateService.cdnVersionUrl,
          contains('raw.githubusercontent.com/AbhiLohar/vitap-backend/main/version.json'));
    });

    test('Web URL points to GitHub releases latest', () {
      expect(UpdateService.releasesWebUrl,
          equals('https://github.com/AbhiLohar/vitap-backend/releases/latest'));
    });

    test('directApkDownloadUrl points to GitHub releases latest direct apk download', () {
      expect(UpdateService.directApkDownloadUrl,
          equals('https://github.com/AbhiLohar/vitap-backend/releases/latest/download/app-release.apk'));
    });

    test('Parses version.json structure properly', () {
      const rawJson = '''{
        "version": "1.0.4",
        "versionCode": 5,
        "title": "Version 1.0.4",
        "notes": "Bug fixes and improvements.",
        "apkUrl": "https://github.com/AbhiLohar/vitap-backend/releases/download/v1.0.4/app-release.apk",
        "releaseUrl": "https://github.com/AbhiLohar/vitap-backend/releases/latest"
      }''';

      final data = json.decode(rawJson) as Map<String, dynamic>;
      final ver = (data["version"] ?? "").toString().replaceAll(RegExp(r'^[v\s]+'), '');
      expect(ver, equals('1.0.4'));
      expect(UpdateService.compareVersions(ver, '1.0.3'), greaterThan(0));
      expect(data["apkUrl"], endsWith('.apk'));
    });

    test('Parses 302 Location header correctly for GitHub web releases', () {
      const location = 'https://github.com/AbhiLohar/vitap-backend/releases/tag/v1.0.4';
      final tagMatch = RegExp(r'releases/tag/([^/?#]+)').firstMatch(location);
      expect(tagMatch, isNotNull);
      final tag = tagMatch!.group(1)!;
      expect(tag, equals('v1.0.4'));
      final ver = tag.replaceAll(RegExp(r'^[v\s]+'), '').trim();
      expect(ver, equals('1.0.4'));
      expect(UpdateService.compareVersions(ver, '1.0.3'), greaterThan(0));
    });
  });
}
