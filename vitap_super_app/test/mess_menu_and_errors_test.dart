import 'dart:convert';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitap_super_app/config/app_theme.dart';
import 'package:vitap_super_app/services/error_formatter.dart' as app_errors;
import 'package:vitap_super_app/services/mess_menu_service.dart';

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 < l2 ? l1 : l2;
  return (hi + 0.05) / (lo + 0.05);
}

xl.CellValue _t(String s) => xl.TextCellValue(s);

void main() {
  group('ErrorFormatter plain-English formatting', () {
    test('translates HTTP and network technical errors cleanly', () {
      final err404 = app_errors.ErrorFormatter.format('Server responded with HTTP 404 while downloading update');
      expect(err404.toLowerCase(), isNot(contains('404')));
      expect(err404.toLowerCase(), isNot(contains('exception')));

      final err502 = app_errors.ErrorFormatter.format('Bad Gateway 502 <html>nginx</html>');
      expect(err502.toLowerCase(), isNot(contains('502')));
      expect(err502.toLowerCase(), contains('restarting'));

      final errSocket = app_errors.ErrorFormatter.format('SocketException: Failed host lookup');
      expect(errSocket.toLowerCase(), isNot(contains('socketexception')));
      expect(errSocket.toLowerCase(), contains('internet'));

      final errTimeout = app_errors.ErrorFormatter.format('TimeoutException after 0:00:30');
      expect(errTimeout.toLowerCase(), isNot(contains('timeoutexception')));
      expect(errTimeout.toLowerCase(), contains('too long'));

      final errFormat = app_errors.ErrorFormatter.format('FormatException: Unexpected character');
      expect(errFormat.toLowerCase(), isNot(contains('formatexception')));

      final errArchive = app_errors.ErrorFormatter.format('ArchiveException: Could not find End of Central Directory');
      expect(errArchive.toLowerCase(), contains('.xlsx'));
      expect(errArchive.toLowerCase(), isNot(contains('archiveexception')));
    });

    test('preserves meaningful VTOP outing rejection details without Exception prefix', () {
      final msg = app_errors.ErrorFormatter.format(
        'Exception: VTOP did not accept this weekend outing. Common reasons: (1) Monday outings are only open on declared holidays.',
      );
      expect(msg.startsWith('Exception:'), isFalse);
      expect(msg, contains('Monday outings'));
    });
  });

  group('MessMenuService VIT-AP Excel parsing', () {
    test('handles MESS TIMINGS box, alternating Tue dates, Lemon/2 Pcs Dosa, and instructions block', () {
      final excel = xl.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet()!;
      excel.rename(defaultSheet, 'Special Mess');
      final s = excel['Special Mess'];

      // Rows 0..5: Title + top-right MESS TIMINGS box in Col D (same column!)
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), _t('VIT-AP SPECIAL MESS MENU - NOV 2026'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1), _t('MESS TIMINGS'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2), _t('BREAKFAST: 7:00 AM - 9:00 AM'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 3), _t('LUNCH: 12:30 PM - 2:15 PM'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 4), _t('SNACKS: 4:30 PM - 6:15 PM'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 5), _t('DINNER: 7:15 PM - 9:00 PM'));

      // Row 7: Real Header row
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7), _t('DAY'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 7), _t('DATES'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7), _t('BREAKFAST'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 7), _t('LUNCH'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7), _t('SNACKS'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 7), _t('DINNER'));

      // Row 8: Tue (3, 17)
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8), _t('TUE'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8), _t('3, 17'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 8), _t('Onion Dosa (3), Masala Dosa (17)\n2 Pcs Dosa\nLemon Juice\nTea/Coffee/Milk'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 8), _t('White Rice\nDal'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 8), _t('Samosa'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 8), _t('Pulka\nPaneer'));

      // Row 9: Tue (10, 24)
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 9), _t('TUE'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 9), _t('10, 24'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 9), _t('Ghee Podi Dosa (2 Pcs Thin)\nPav Bhaji\nTea/Coffee/Milk'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 9), _t('Rajma Masala\nWhite Rice'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 9), _t('Punugulu'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 9), _t('Dal Makhani\nPulka'));

      // Row 10: Wed (4, 18) with Lemon (must NOT match Mon!) and Fri word inside 'Fried Rice' (must NOT match Fri!)
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 10), _t('WED'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 10), _t('4, 18'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 10), _t('1. Idly - 4 Pcs\nLemon Water'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 10), _t('Veg Fried Rice'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 10), _t('Aloo Samosa'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 10), _t('Chapathi'));

      // Row 12: MESS SERVICE INSTRUCTIONS followed by policy rules that must NEVER leak into Wed!
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 12), _t('MESS SERVICE INSTRUCTIONS'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 13), _t('Food must be cooked using good-quality oil as per the menu.'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 14), _t('Weighing machine must be kept functional before serving every day.'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 15), _t('Sona Masuri rice only should be used.'));

      // Row 17: Stacked Veg & Non-Veg section below on SAME sheet!
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 17), _t('VEG & NON-VEG MESS MENU'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 18), _t('DAY'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 18), _t('BREAKFAST'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 18), _t('LUNCH'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 18), _t('SNACKS'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 18), _t('DINNER'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 19), _t('SUN'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 19), _t('Chole Bhature'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 19), _t('Chicken Biryani'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 19), _t('Dahi Puri'));
      s.updateCell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 19), _t('Aloo Gobi'));

      final bytes = excel.encode()!;
      final parsed = MessMenuService.parseExcelWorkbookStrict(bytes);

      expect(parsed.containsKey('special'), isTrue);
      expect(parsed.containsKey('veg_nonveg'), isTrue);

      final special = parsed['special']!;
      // Date 3 and Date 24 must stay completely isolated!
      expect(special['Date_3']!['Breakfast'], contains('Onion Dosa (3), Masala Dosa (17)'));
      expect(special['Date_3']!['Breakfast'], contains('2 Pcs Dosa'));
      expect(special['Date_3']!['Breakfast'], contains('Lemon Juice'));
      expect(special['Date_3']!['Breakfast'], isNot(contains('Ghee Podi Dosa (2 Pcs Thin)')));

      expect(special['Date_24']!['Breakfast'], contains('Ghee Podi Dosa (2 Pcs Thin)'));
      expect(special['Date_24']!['Breakfast'], isNot(contains('Onion Dosa (3), Masala Dosa (17)')));

      // Listed numbers in Breakfast ("1. Idly - 4 Pcs") strips list marker; "2 Pcs Dosa" keeps "2 "
      expect(special['Date_4']!['Breakfast'], contains('Idly - 4 Pcs'));

      // Policy instructions never appear anywhere in Wed / Date_4 / Mon / Fri
      expect(special.containsKey('Mon'), isFalse);
      expect(special.containsKey('Fri'), isFalse);
      final wedAll = special['Date_4']!.values.expand((e) => e).join(' ');
      expect(wedAll.toLowerCase(), isNot(contains('weighing machine')));
      expect(wedAll.toLowerCase(), isNot(contains('good-quality')));
      expect(wedAll.toLowerCase(), isNot(contains('sona masuri')));

      // Stacked section separated cleanly into veg_nonveg
      expect(parsed['veg_nonveg']!['Sun']!['Breakfast'], contains('Chole Bhature'));
    });

    test('parseExcelWorkbookStrict throws readable error on non-xlsx bytes', () {
      final invalidBytes = utf8.encode('%PDF-1.4 fake legacy binary');
      expect(
        () => MessMenuService.parseExcelWorkbookStrict(invalidBytes),
        throwsA(predicate((e) => e.toString().contains('.xlsx'))),
      );
    });
  });

  group('AppTheme contrast & adaptive colors', () {
    testWidgets('all themes maintain strong foreground/background contrast', (tester) async {
      final themes = {
        'light': AppTheme.lightTheme,
        'dark': AppTheme.darkTheme,
        'nightfall': AppTheme.nightfallTheme,
        'sakura': AppTheme.sakuraTheme,
      };

      for (final entry in themes.entries) {
        final name = entry.key;
        final theme = entry.value;
        final cardBg = theme.cardTheme.color!;
        final primary = theme.colorScheme.primary;
        final onPrimary = theme.colorScheme.onPrimary;
        final bodyLarge = theme.textTheme.bodyLarge!.color!;
        final bodyMedium = theme.textTheme.bodyMedium!.color!;
        final bodySmall = theme.textTheme.bodySmall!.color!;

        expect(
          _contrastRatio(primary, cardBg),
          greaterThanOrEqualTo(4.5),
          reason: '$name theme primary must stand out clearly on card background',
        );
        expect(
          _contrastRatio(theme.primaryColor, cardBg),
          greaterThanOrEqualTo(4.5),
          reason: '$name theme primaryColor must not be dark-on-dark',
        );
        expect(
          _contrastRatio(onPrimary, primary),
          greaterThanOrEqualTo(4.5),
          reason: '$name theme onPrimary text/icon must stay legible on primary fill',
        );
        expect(_contrastRatio(bodyLarge, cardBg), greaterThanOrEqualTo(7.0));
        expect(_contrastRatio(bodyMedium, cardBg), greaterThanOrEqualTo(4.5));
        expect(_contrastRatio(bodySmall, cardBg), greaterThanOrEqualTo(4.5));

        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(name),
            theme: theme,
            home: Builder(
              builder: (context) {
                expect(AppColors.adaptivePrimary(context), equals(primary));
                expect(_contrastRatio(AppColors.onPrimary(context), primary), greaterThanOrEqualTo(4.5));
                expect(_contrastRatio(AppColors.adaptiveGreen(context), cardBg), greaterThanOrEqualTo(4.5));
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      }
    });
  });
}
