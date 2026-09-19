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
    });

    test('handles multi-digit semantic numbers correctly (1.10.0 > 1.9.0)', () {
      expect(UpdateService.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(UpdateService.compareVersions('1.2.0', '1.10.0'), lessThan(0));
    });

    test('handles build metadata (+1)', () {
      expect(UpdateService.compareVersions('1.0.1+2', '1.0.0+1'), greaterThan(0));
    });
  });
}
