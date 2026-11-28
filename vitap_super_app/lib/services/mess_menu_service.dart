import 'dart:convert';
import 'package:excel/excel.dart' as xl;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing mess menu data — parsing, storage, retrieval.
class MessMenuService {
  static const _keyPrefix = 'mess_menu_';

  static const List<String> mealOrder = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'];
  static const List<String> dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Meal emojis
  static const Map<String, String> mealEmoji = {
    'Breakfast': '🌅',
    'Lunch': '☀️',
    'Snacks': '☕',
    'Dinner': '🌙',
  };

  // Meal time display strings
  static const Map<String, String> mealTimeDisplay = {
    'Breakfast': '7:00 AM – 9:00 AM',
    'Lunch': '12:30 PM – 2:15 PM',
    'Snacks': '4:30 PM – 6:15 PM',
    'Dinner': '7:15 PM – 9:00 PM',
  };

  // ── Storage ──

  static Future<void> saveMenu(String messType, Map<String, Map<String, List<String>>> menu) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, Map<String, List<String>>> cleanMenu = {};
    
    menu.forEach((day, meals) {
      final dayStr = day.toString();
      cleanMenu[dayStr] = {};
      meals.forEach((meal, items) {
        cleanMenu[dayStr]![meal.toString()] = items.map((e) => e.toString()).toList();
      });
    });
    
    await prefs.setString('$_keyPrefix$messType', jsonEncode(cleanMenu));
  }

  static Future<Map<String, Map<String, List<String>>>> loadMenu(String messType) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$messType');
    if (raw == null || raw.trim().isEmpty) return {};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final Map<String, Map<String, List<String>>> menu = {};
      decoded.forEach((dayKey, mealsObj) {
        final day = dayKey.toString();
        menu[day] = {};
        if (mealsObj is Map) {
          mealsObj.forEach((mealKey, itemsObj) {
            final meal = mealKey.toString();
            if (itemsObj is List) {
              final seen = <String>{};
              final cleanItems = <String>[];
              for (final e in itemsObj) {
                final str = e.toString().trim();
                if (str.isEmpty) continue;
                if (_isInstructionSentence(str)) continue;
                if (seen.add(str.toLowerCase())) {
                  cleanItems.add(str);
                }
              }
              menu[day]![meal] = cleanItems;
            }
          });
        }
      });
      return menu;
    } catch (e) {
      print('[MessMenu] Error loading menu for $messType: $e');
      return {};
    }
  }

  static Future<bool> hasMenu(String messType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_keyPrefix$messType');
  }

  static Future<void> clearMenu(String messType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$messType');
  }

  /// Clean, deduplicate and sanitize all stored menus on the device
  static Future<void> cleanAndDeduplicateStoredMenus() async {
    for (final messType in ['special', 'veg_nonveg']) {
      final menu = await loadMenu(messType);
      if (menu.isEmpty) continue;
      final clean = <String, Map<String, List<String>>>{};
      menu.forEach((key, meals) {
        clean[key] = _deduplicateMealMap(meals);
      });
      await saveMenu(messType, clean);
    }
  }

  // ── Retrieval ──

  /// Get menu for a day name or specific date number (e.g. dateNum = 24 for 24th of the month)
  static Future<Map<String, List<String>>> getMenuForDayOrDate(
    String messType, {
    required String dayName,
    int? dateNum,
  }) async {
    final menu = await loadMenu(messType);
    if (menu.isEmpty) return {};

    // 1. Try date-specific key first (e.g. Date_24)
    if (dateNum != null) {
      final dateKey = 'Date_$dateNum';
      if (menu.containsKey(dateKey)) {
        final dateMenu = menu[dateKey]!;
        if (_hasAnyMealItems(dateMenu)) {
          return _deduplicateMealMap(dateMenu);
        }
      }

      // If exact date key was not found, check week-of-month cycle first (1..5),
      // then alternating 2-cycle fallback (Cycle 1: days 1–7 & 15–21, Cycle 2: days 8–14 & 22–28)
      final weekNum = ((dateNum - 1) ~/ 7) + 1;
      final weekKey = '${dayName}_Cycle$weekNum';
      if (menu.containsKey(weekKey)) {
        final weekMenu = menu[weekKey]!;
        if (_hasAnyMealItems(weekMenu)) {
          return _deduplicateMealMap(weekMenu);
        }
      }

      final cycle = ((dateNum - 1) ~/ 7) % 2 + 1;
      final cycleKey = '${dayName}_Cycle$cycle';
      if (menu.containsKey(cycleKey)) {
        final cycleMenu = menu[cycleKey]!;
        if (_hasAnyMealItems(cycleMenu)) {
          return _deduplicateMealMap(cycleMenu);
        }
      }
    }

    // 2. Fall back to day name (e.g. 'Tue', 'Wed')
    if (menu.containsKey(dayName)) {
      final dayMenu = menu[dayName]!;
      if (_hasAnyMealItems(dayMenu)) {
        return _deduplicateMealMap(dayMenu);
      }
    }

    // 3. Fall back to case-insensitive match
    for (final key in menu.keys) {
      if (key.toLowerCase().startsWith(dayName.toLowerCase())) {
        final m = menu[key]!;
        if (_hasAnyMealItems(m)) {
          return _deduplicateMealMap(m);
        }
      }
    }

    return {};
  }

  static bool _hasAnyMealItems(Map<String, List<String>> mealMap) {
    return mealMap.values.any((list) => list.isNotEmpty);
  }

  static Map<String, List<String>> _deduplicateMealMap(Map<String, List<String>> raw) {
    final clean = <String, List<String>>{};
    for (final meal in mealOrder) {
      final items = raw[meal] ?? [];
      final seen = <String>{};
      final uniqueItems = <String>[];
      for (final item in items) {
        final trimmed = item.trim();
        if (trimmed.isEmpty) continue;
        if (_isInstructionSentence(trimmed)) continue;
        if (seen.add(trimmed.toLowerCase())) {
          uniqueItems.add(trimmed);
        }
      }
      clean[meal] = uniqueItems;
    }
    return clean;
  }

  /// Legacy getter
  static Future<Map<String, List<String>>> getMenuForDay(String messType, String day) async {
    return getMenuForDayOrDate(messType, dayName: day);
  }

  static Future<void> updateMealItems(String messType, String dayOrDateKey, String mealType, List<String> items) async {
    final menu = await loadMenu(messType);
    menu[dayOrDateKey] ??= {};
    menu[dayOrDateKey]![mealType] = items;
    await saveMenu(messType, menu);
  }

  static String getTodayDay() {
    return dayOrder[DateTime.now().weekday - 1];
  }

  /// Get the current/upcoming meal name based on time.
  static String getUpcomingMealName() {
    final now = DateTime.now();
    final time = now.hour * 60 + now.minute;

    if (time < 9 * 60 + 15) return 'Breakfast';
    if (time < 14 * 60 + 15) return 'Lunch';
    if (time < 18 * 60 + 15) return 'Snacks';
    return 'Dinner';
  }

  static Future<Map<String, dynamic>> getUpcomingMeal(String messType) async {
    final now = DateTime.now();
    final day = getTodayDay();
    final dateNum = now.day;
    final mealName = getUpcomingMealName();
    final dayMenu = await getMenuForDayOrDate(messType, dayName: day, dateNum: dateNum);
    return {
      'day': day,
      'meal': mealName,
      'items': dayMenu[mealName] ?? [],
    };
  }

  // ── Excel Parsing ──

  static bool _isDayHeader(String val) =>
      val == 'day' ||
      val == 'days' ||
      val.contains('weekday') ||
      val.contains('day name') ||
      val.contains('day & date') ||
      val.contains('day/date') ||
      val.contains('days/dates') ||
      val.contains('day & dates') ||
      val.contains('days and dates');

  static bool _isDateHeader(String val) =>
      val == 'date' ||
      val == 'dates' ||
      val == 'dt' ||
      val.contains('date(s)') ||
      val.contains('dates of month') ||
      val.contains('dates of the month');

  static bool _isBreakfastHeader(String val) =>
      val.contains('breakfast') ||
      val.contains('break-fast') ||
      val.contains('break fast') ||
      val.contains('tiffin') ||
      val.contains('morning meal');

  static bool _isLunchHeader(String val) =>
      val.contains('lunch') || val.contains('afternoon meal');

  static bool _isSnacksHeader(String val) =>
      val.contains('snack') ||
      val.contains('hi-tea') ||
      val.contains('hi tea') ||
      val.contains('tea/coffee') ||
      val.contains('refreshment') ||
      val.contains('evening meal');

  static bool _isDinnerHeader(String val) =>
      val.contains('dinner') || val.contains('night meal') || val.contains('supper');

  static bool _isTimingsSummaryRow(xl.Sheet sheet, int row) {
    for (int c = 0; c < sheet.maxColumns; c++) {
      final v = _cellValue(sheet, row, c).toLowerCase();
      if (v.isEmpty) continue;
      if (v.contains('mess timings') ||
          v.contains('mess timing') ||
          RegExp(r'\b\d+(?:\.\d+)?\s*(?:am|pm)\s*(?:to|-|–)\s*\d+').hasMatch(v)) {
        return true;
      }
    }
    return false;
  }

  /// Detect header column positions on row [r]. Returns null unless at least 2 distinct meal columns exist.
  static Map<String, int>? _detectHeaderRowCols(xl.Sheet sheet, int r) {
    if (_isTimingsSummaryRow(sheet, r)) return null;

    int rDay = -1;
    int rDate = -1;
    int rBreakfast = -1;
    int rLunch = -1;
    int rSnacks = -1;
    int rDinner = -1;

    for (int c = 0; c < sheet.maxColumns; c++) {
      final val = _cellValue(sheet, r, c).toLowerCase().trim();
      if (val.isEmpty) continue;
      if (val.length > 35 || _isInstructionSentence(val)) continue;

      if (rDay < 0 && _isDayHeader(val)) {
        rDay = c;
      } else if (rDate < 0 && _isDateHeader(val)) {
        rDate = c;
      } else if (rBreakfast < 0 && _isBreakfastHeader(val)) {
        rBreakfast = c;
      } else if (rLunch < 0 && _isLunchHeader(val)) {
        rLunch = c;
      } else if (rSnacks < 0 && _isSnacksHeader(val)) {
        rSnacks = c;
      } else if (rDinner < 0 && _isDinnerHeader(val)) {
        rDinner = c;
      }
    }

    // Check previous 2 rows for a vertically merged Day/Date header left of Breakfast
    if (rBreakfast >= 0 && rDay < 0 && rDate < 0) {
      for (int prev = r - 1; prev >= 0 && prev >= r - 2; prev--) {
        if (_isTimingsSummaryRow(sheet, prev)) continue;
        for (int c = 0; c < rBreakfast; c++) {
          final val = _cellValue(sheet, prev, c).toLowerCase().trim();
          if (val.isEmpty) continue;
          if (rDay < 0 && _isDayHeader(val)) rDay = c;
          if (rDate < 0 && _isDateHeader(val)) rDate = c;
        }
      }
    }

    final distinctMealCols = [rBreakfast, rLunch, rSnacks, rDinner].where((c) => c >= 0).toSet();
    if (rBreakfast >= 0 &&
        distinctMealCols.length >= 2 &&
        (rLunch < 0 || rLunch > rBreakfast) &&
        (rDay < 0 || rDay < rBreakfast) &&
        (rDate < 0 || rDate < rBreakfast)) {
      return {
        'dayCol': rDay,
        'dateCol': rDate,
        'breakfastCol': rBreakfast,
        'lunchCol': rLunch,
        'snacksCol': rSnacks,
        'dinnerCol': rDinner,
      };
    }
    return null;
  }

  /// Inspect rows above [endRow] (typically start of sheet or section) to infer 'special' vs 'veg_nonveg'.
  static String _inferMessTypeFromSheetContext(xl.Sheet sheet, String sheetName, int startRow, int endRow) {
    final lowerSheet = sheetName.toLowerCase().trim();
    if (lowerSheet.contains('special')) return 'special';
    if (lowerSheet.contains('veg') ||
        lowerSheet.contains('non') ||
        lowerSheet.contains('regular') ||
        lowerSheet.contains('general') ||
        lowerSheet.contains('normal')) {
      return 'veg_nonveg';
    }

    for (int r = startRow; r < sheet.maxRows && r <= endRow; r++) {
      for (int c = 0; c < sheet.maxColumns; c++) {
        final v = _cellValue(sheet, r, c).toLowerCase();
        if (v.isEmpty) continue;
        if (v.contains('special mess') || (v.contains('special') && v.contains('menu'))) {
          return 'special';
        }
        if (v.contains('veg & non') ||
            v.contains('veg and non') ||
            v.contains('non-veg') ||
            v.contains('non veg') ||
            v.contains('regular mess') ||
            v.contains('general mess') ||
            v.contains('normal mess')) {
          return 'veg_nonveg';
        }
      }
    }
    return '';
  }

  /// Parse entire Excel workbook into mess types (e.g. 'veg_nonveg' -> menu, 'special' -> menu).
  /// Supports multiple sheets AND stacked Special / Veg & Non-Veg sections inside one sheet.
  static Map<String, Map<String, Map<String, List<String>>>> parseExcelWorkbook(List<int> bytes) {
    try {
      return parseExcelWorkbookStrict(bytes);
    } catch (e) {
      print('[MessMenu] Excel workbook parse error: $e');
      return {};
    }
  }

  /// Strict variant that surfaces readable errors when an Excel file is invalid or unsupported.
  static Map<String, Map<String, Map<String, List<String>>>> parseExcelWorkbookStrict(List<int> bytes) {
    final result = <String, Map<String, Map<String, List<String>>>>{};
    final xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (e) {
      final raw = e.toString().toLowerCase();
      if (raw.contains('archive') || raw.contains('central directory') || raw.contains('zip')) {
        throw Exception('This file is not a valid modern Excel (.xlsx) workbook. If it is an older .xls or PDF file, please save/export it as .xlsx or .csv and try again.');
      }
      throw Exception('Could not open the Excel file. Please verify it is a valid .xlsx document.');
    }

    if (excel.tables.isEmpty) {
      throw Exception('The selected Excel file has no sheets.');
    }

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName]!;
      final lowerSheet = sheetName.toLowerCase().trim();

      // Skip non-menu sheets (instructions, rules, summary, etc.)
      if (lowerSheet.contains('instruction') ||
          lowerSheet.contains('guideline') ||
          lowerSheet.contains('rule') ||
          lowerSheet.contains('cover') ||
          lowerSheet.contains('summary') ||
          lowerSheet.contains('notice') ||
          lowerSheet.contains('template') ||
          lowerSheet.contains('feedback')) {
        continue;
      }

      final sections = _parseSheetSections(sheet, sheetName);
      for (final section in sections) {
        final inferredType = section['type'] as String;
        final sectionMenu = section['menu'] as Map<String, Map<String, List<String>>>;
        if (sectionMenu.isEmpty) continue;

        if (inferredType == 'special' && !result.containsKey('special')) {
          result['special'] = sectionMenu;
        } else if (inferredType == 'veg_nonveg' && !result.containsKey('veg_nonveg')) {
          result['veg_nonveg'] = sectionMenu;
        } else if (!result.containsKey('veg_nonveg')) {
          result['veg_nonveg'] = sectionMenu;
        } else if (!result.containsKey('special')) {
          result['special'] = sectionMenu;
        }
      }
    }

    // If only 1 menu was parsed from the workbook, mirror to both keys so either tab displays cleanly
    if (result.length == 1) {
      final existingKey = result.keys.first;
      final otherKey = existingKey == 'special' ? 'veg_nonveg' : 'special';
      result[otherKey] = result[existingKey]!;
    }
    return result;
  }

  /// Parse a single Excel sheet into a date-aware weekly/monthly menu (first menu table on the sheet).
  static Map<String, Map<String, List<String>>> parseSingleSheet(xl.Sheet sheet) {
    final sections = _parseSheetSections(sheet, sheet.sheetName);
    if (sections.isEmpty) return {};
    return sections.first['menu'] as Map<String, Map<String, List<String>>>;
  }

  static List<Map<String, dynamic>> _parseSheetSections(xl.Sheet sheet, String sheetName) {
    final sections = <Map<String, dynamic>>[];
    int searchFrom = 0;

    while (searchFrom < sheet.maxRows) {
      int headerRow = -1;
      Map<String, int>? cols;

      final scanLimit = (searchFrom + 30 < sheet.maxRows) ? searchFrom + 30 : sheet.maxRows;
      for (int r = searchFrom; r < scanLimit; r++) {
        cols = _detectHeaderRowCols(sheet, r);
        if (cols != null) {
          headerRow = r;
          break;
        }
      }

      // Single fallback if no explicit multi-column header was found in initial scan
      if (headerRow < 0 && searchFrom == 0) {
        for (int r = 0; r < sheet.maxRows && r < 25; r++) {
          if (_isTimingsSummaryRow(sheet, r)) continue;
          for (int c = 0; c < sheet.maxColumns; c++) {
            final val = _cellValue(sheet, r, c).toLowerCase();
            if (_isBreakfastHeader(val)) {
              cols = {
                'dayCol': c > 0 ? c - 1 : 0,
                'dateCol': -1,
                'breakfastCol': c,
                'lunchCol': -1,
                'snacksCol': -1,
                'dinnerCol': -1,
              };
              headerRow = r;
              break;
            }
          }
          if (headerRow >= 0) break;
        }
      }

      if (headerRow < 0 || cols == null) break;

      int dayCol = cols['dayCol'] ?? -1;
      final int dateCol = cols['dateCol'] ?? -1;
      final int breakfastCol = cols['breakfastCol'] ?? -1;
      if (breakfastCol < 0) break;

      if (dayCol < 0) {
        dayCol = (dateCol >= 0 && dateCol > 0)
            ? dateCol - 1
            : (breakfastCol > 0 ? breakfastCol - 1 : 0);
      }
      final int lunchCol = (cols['lunchCol'] ?? -1) >= 0 ? cols['lunchCol']! : breakfastCol + 1;
      final int snacksCol = (cols['snacksCol'] ?? -1) >= 0 ? cols['snacksCol']! : lunchCol + 1;
      final int dinnerCol = (cols['dinnerCol'] ?? -1) >= 0 ? cols['dinnerCol']! : snacksCol + 1;

      final menu = <String, Map<String, List<String>>>{};
      String currentDayName = '';
      List<int> currentDates = [];
      int cycleCount = 1;
      final seenDaysInCycle = <String>{};
      int nextRowAfterSection = sheet.maxRows;

      for (int r = headerRow + 1; r < sheet.maxRows; r++) {
        // 1. Stop if a new menu table header starts further down the same sheet
        if (_detectHeaderRowCols(sheet, r) != null) {
          nextRowAfterSection = r;
          break;
        }

        // 2. Check if row is an instruction / terms section header — stop this table!
        if (_isInstructionRow(sheet, r)) {
          // Keep scanning after instructions in case another menu section follows later
          nextRowAfterSection = r + 1;
          break;
        }

        // Ignore summary timings box rows if any appear stray
        if (_isTimingsSummaryRow(sheet, r)) {
          continue;
        }

        // 3. Extract day name and dates strictly from columns left of breakfastCol
        String rowDayName = '';
        List<int> rowDates = [];

        final colsToCheck = <int>{
          if (dayCol >= 0 && dayCol < breakfastCol) dayCol,
          if (dateCol >= 0 && dateCol < breakfastCol) dateCol,
          for (int c = 0; c < breakfastCol; c++) c,
        };

        for (final c in colsToCheck) {
          final cellText = _cellValue(sheet, r, c).trim();
          if (cellText.isEmpty) continue;

          if (rowDayName.isEmpty) {
            final norm = _normalizeDayName(cellText);
            if (norm.isNotEmpty) {
              rowDayName = norm;
            }
          }

          final extracted = _extractDates(cellText);
          if (extracted.isNotEmpty) {
            rowDates.addAll(extracted);
          }
        }
        rowDates = rowDates.toSet().toList()..sort();

        // 4. Update day name & track weekly cycles accurately (regardless of whether table starts on Sat, Sun, or Mon)
        if (rowDayName.isNotEmpty) {
          if (seenDaysInCycle.contains(rowDayName)) {
            cycleCount++;
            seenDaysInCycle.clear();
          }
          seenDaysInCycle.add(rowDayName);
          currentDayName = rowDayName;
          currentDates = rowDates;
        } else if (rowDates.isNotEmpty) {
          currentDates = rowDates;
        }

        if (currentDayName.isEmpty) continue;

        // 5. Extract meal items
        final breakfast = _splitItems(_cellValue(sheet, r, breakfastCol));
        final lunch = _splitItems(_cellValue(sheet, r, lunchCol));
        final snacks = _splitItems(_cellValue(sheet, r, snacksCol));
        final dinner = _splitItems(_cellValue(sheet, r, dinnerCol));

        if (breakfast.isEmpty && lunch.isEmpty && snacks.isEmpty && dinner.isEmpty) {
          continue;
        }

        if (_isAllInstructions(breakfast, lunch, snacks, dinner)) {
          continue;
        }

        final mealData = {
          'Breakfast': breakfast,
          'Lunch': lunch,
          'Snacks': snacks,
          'Dinner': dinner,
        };

        final bool isContinuationRow = rowDayName.isEmpty && rowDates.isEmpty;

        // 6. Store by specific date numbers (e.g. Date_3, Date_10, Date_17, Date_24)
        if (currentDates.isNotEmpty) {
          for (final dateNum in currentDates) {
            final key = 'Date_$dateNum';
            if (menu[key] == null) {
              menu[key] = {
                'Breakfast': List.from(breakfast),
                'Lunch': List.from(lunch),
                'Snacks': List.from(snacks),
                'Dinner': List.from(dinner),
              };
            } else if (isContinuationRow || (menu[key]!['Breakfast']!.isEmpty && breakfast.isNotEmpty)) {
              // Append only if it's an overflow continuation row or filling an empty meal slot
              _appendMealItems(menu[key]!, mealData);
            }
          }
        }

        // 7. Store under day name fallback ('Tue', 'Wed', etc.) without stacking duplicate cycles
        if (cycleCount <= 1) {
          if (menu[currentDayName] == null) {
            menu[currentDayName] = {
              'Breakfast': List.from(breakfast),
              'Lunch': List.from(lunch),
              'Snacks': List.from(snacks),
              'Dinner': List.from(dinner),
            };
          } else if (isContinuationRow) {
            _appendMealItems(menu[currentDayName]!, mealData);
          }
        } else {
          final cycleKey = '${currentDayName}_Cycle$cycleCount';
          if (menu[cycleKey] == null) {
            menu[cycleKey] = {
              'Breakfast': List.from(breakfast),
              'Lunch': List.from(lunch),
              'Snacks': List.from(snacks),
              'Dinner': List.from(dinner),
            };
          } else if (isContinuationRow) {
            _appendMealItems(menu[cycleKey]!, mealData);
          }
        }
      }

      if (menu.isNotEmpty) {
        final inferredType = _inferMessTypeFromSheetContext(sheet, sheetName, searchFrom, headerRow);
        sections.add({
          'type': inferredType,
          'menu': menu,
        });
      }

      searchFrom = nextRowAfterSection;
    }

    return sections;
  }

  static String _cellValue(xl.Sheet sheet, int row, int col) {
    if (row >= sheet.maxRows || col >= sheet.maxColumns || col < 0) return '';
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    final v = cell.value;
    if (v == null) return '';
    if (v is xl.TextCellValue) {
      return v.value.toString().trim();
    }
    if (v is xl.DateCellValue) {
      return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
    }
    if (v is xl.DateTimeCellValue) {
      return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
    }
    return v.toString().trim();
  }

  /// Parse CSV text into a date-aware menu
  static Map<String, Map<String, List<String>>> parseCsvText(String csvText) {
    final menu = <String, Map<String, List<String>>>{};
    final lines = csvText.split('\n');

    int headerIdx = -1;
    int dayCol = -1;
    int dateCol = -1;
    int breakfastCol = -1;
    int lunchCol = -1;
    int snacksCol = -1;
    int dinnerCol = -1;

    for (int i = 0; i < lines.length && i < 25; i++) {
      final lower = lines[i].toLowerCase();
      if (lower.contains('mess timings') || RegExp(r'\b\d+(?:\.\d+)?\s*(?:am|pm)\s*(?:to|-|–)\s*\d+').hasMatch(lower)) {
        continue;
      }

      final cells = _splitCsvLine(lines[i]);
      int rDay = -1, rDate = -1, rBreakfast = -1, rLunch = -1, rSnacks = -1, rDinner = -1;
      for (int c = 0; c < cells.length; c++) {
        final val = cells[c].toLowerCase().trim();
        if (val.isEmpty) continue;
        if (rDay < 0 && _isDayHeader(val)) {
          rDay = c;
        } else if (rDate < 0 && _isDateHeader(val)) {
          rDate = c;
        } else if (rBreakfast < 0 && _isBreakfastHeader(val)) {
          rBreakfast = c;
        } else if (rLunch < 0 && _isLunchHeader(val)) {
          rLunch = c;
        } else if (rSnacks < 0 && _isSnacksHeader(val)) {
          rSnacks = c;
        } else if (rDinner < 0 && _isDinnerHeader(val)) {
          rDinner = c;
        }
      }

      final mealCols = [rBreakfast, rLunch, rSnacks, rDinner].where((c) => c >= 0).toSet();
      if (rBreakfast >= 0 && mealCols.length >= 2 && (rDay < 0 || rDay < rBreakfast)) {
        headerIdx = i;
        dayCol = rDay >= 0 ? rDay : (rBreakfast > 0 ? rBreakfast - 1 : 0);
        dateCol = rDate;
        breakfastCol = rBreakfast;
        lunchCol = rLunch >= 0 ? rLunch : rBreakfast + 1;
        snacksCol = rSnacks >= 0 ? rSnacks : lunchCol + 1;
        dinnerCol = rDinner >= 0 ? rDinner : snacksCol + 1;
        break;
      }
    }
    if (headerIdx == -1 && lines.length > 1) {
      headerIdx = 0;
      dayCol = 0;
      breakfastCol = 1;
      lunchCol = 2;
      snacksCol = 3;
      dinnerCol = 4;
    }
    if (headerIdx == -1 || breakfastCol < 0) return menu;

    String currentDayName = '';
    List<int> currentDates = [];
    int cycleCount = 1;
    final seenDaysInCycle = <String>{};

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final upperLine = line.toUpperCase();
      if (upperLine.contains('MESS SERVICE INSTRUCTION') ||
          upperLine.contains('SERVICE INSTRUCTION') ||
          upperLine.contains('GENERAL INSTRUCTION') ||
          upperLine.contains('SPECIAL INSTRUCTION') ||
          upperLine.contains('RULES AND REGULATION') ||
          upperLine.contains('TERMS AND CONDITION') ||
          upperLine.startsWith('NOTE:') ||
          upperLine.startsWith('NOTES:')) {
        break;
      }

      final cells = _splitCsvLine(line);
      final maxCol = [breakfastCol, lunchCol, snacksCol, dinnerCol].reduce((a, b) => a > b ? a : b);
      if (cells.length <= maxCol) continue;

      String rowDayName = '';
      List<int> rowDates = [];

      final colsToCheck = <int>{
        if (dayCol >= 0 && dayCol < cells.length) dayCol,
        if (dateCol >= 0 && dateCol < cells.length) dateCol,
        for (int c = 0; c < breakfastCol && c < cells.length; c++) c,
      };

      for (final c in colsToCheck) {
        final cellText = cells[c].trim();
        if (cellText.isEmpty) continue;

        if (rowDayName.isEmpty) {
          final norm = _normalizeDayName(cellText);
          if (norm.isNotEmpty) rowDayName = norm;
        }

        final extracted = _extractDates(cellText);
        if (extracted.isNotEmpty) rowDates.addAll(extracted);
      }
      rowDates = rowDates.toSet().toList()..sort();

      if (rowDayName.isNotEmpty) {
        if (seenDaysInCycle.contains(rowDayName)) {
          cycleCount++;
          seenDaysInCycle.clear();
        }
        seenDaysInCycle.add(rowDayName);
        currentDayName = rowDayName;
        currentDates = rowDates;
      } else if (rowDates.isNotEmpty) {
        currentDates = rowDates;
      }

      if (currentDayName.isEmpty) continue;

      final breakfast = _splitItems(cells[breakfastCol]);
      final lunch = _splitItems(cells[lunchCol]);
      final snacks = _splitItems(cells[snacksCol]);
      final dinner = _splitItems(cells[dinnerCol]);

      if (breakfast.isEmpty && lunch.isEmpty && snacks.isEmpty && dinner.isEmpty) continue;
      if (_isAllInstructions(breakfast, lunch, snacks, dinner)) continue;

      final mealData = {
        'Breakfast': breakfast,
        'Lunch': lunch,
        'Snacks': snacks,
        'Dinner': dinner,
      };
      final bool isContinuationRow = rowDayName.isEmpty && rowDates.isEmpty;

      if (currentDates.isNotEmpty) {
        for (int dateNum in currentDates) {
          final key = 'Date_$dateNum';
          if (menu[key] == null) {
            menu[key] = {
              'Breakfast': List.from(breakfast),
              'Lunch': List.from(lunch),
              'Snacks': List.from(snacks),
              'Dinner': List.from(dinner),
            };
          } else if (isContinuationRow || (menu[key]!['Breakfast']!.isEmpty && breakfast.isNotEmpty)) {
            _appendMealItems(menu[key]!, mealData);
          }
        }
      }

      if (cycleCount <= 1) {
        if (menu[currentDayName] == null) {
          menu[currentDayName] = {
            'Breakfast': List.from(breakfast),
            'Lunch': List.from(lunch),
            'Snacks': List.from(snacks),
            'Dinner': List.from(dinner),
          };
        } else if (isContinuationRow) {
          _appendMealItems(menu[currentDayName]!, mealData);
        }
      } else {
        final cycleKey = '${currentDayName}_Cycle$cycleCount';
        if (menu[cycleKey] == null) {
          menu[cycleKey] = {
            'Breakfast': List.from(breakfast),
            'Lunch': List.from(lunch),
            'Snacks': List.from(snacks),
            'Dinner': List.from(dinner),
          };
        } else if (isContinuationRow) {
          _appendMealItems(menu[cycleKey]!, mealData);
        }
      }
    }
    return menu;
  }

  static List<String> _splitCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    StringBuffer current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }

  static void _appendMealItems(
    Map<String, List<String>> target,
    Map<String, List<String>> incoming,
  ) {
    for (final meal in mealOrder) {
      final existing = target[meal] ?? [];
      final seen = existing.map((e) => e.toLowerCase().trim()).toSet();
      final toAdd = incoming[meal] ?? [];
      for (final item in toAdd) {
        final trimmed = item.trim();
        if (trimmed.isEmpty) continue;
        if (_isInstructionSentence(trimmed)) continue;
        if (seen.add(trimmed.toLowerCase())) {
          existing.add(trimmed);
        }
      }
      target[meal] = existing;
    }
  }

  static bool _isInstructionRow(xl.Sheet sheet, int row) {
    for (int c = 0; c < sheet.maxColumns; c++) {
      final cellText = _cellValue(sheet, row, c).toUpperCase().trim();
      if (cellText.isEmpty) continue;

      if (cellText.contains('MESS SERVICE INSTRUCTION') ||
          cellText.contains('SERVICE INSTRUCTION') ||
          cellText.contains('GENERAL INSTRUCTION') ||
          cellText.contains('SPECIAL INSTRUCTION') ||
          cellText.contains('IMPORTANT INSTRUCTION') ||
          cellText.contains('INSTRUCTIONS TO') ||
          cellText.contains('INSTRUCTIONS:') ||
          cellText == 'INSTRUCTIONS' ||
          cellText == 'INSTRUCTION' ||
          cellText.startsWith('NOTE:') ||
          cellText.startsWith('NOTES:') ||
          cellText.contains('TERMS & CONDITIONS') ||
          cellText.contains('TERMS AND CONDITIONS') ||
          cellText.contains('RULES & REGULATIONS') ||
          cellText.contains('RULES AND REGULATIONS') ||
          cellText.contains('CATERER GUIDELINE') ||
          cellText.contains('PENALTY CLAUSE') ||
          cellText.contains('FEEDBACK / COMPLAINT') ||
          cellText.contains('MESS COMMITTEE') ||
          cellText.contains('FOOD COMMITTEE')) {
        return true;
      }
    }
    return false;
  }

  static bool _isAllInstructions(
    List<String> breakfast,
    List<String> lunch,
    List<String> snacks,
    List<String> dinner,
  ) {
    final all = [...breakfast, ...lunch, ...snacks, ...dinner];
    if (all.isEmpty) return false;
    return all.every((item) => _isInstructionSentence(item));
  }

  /// Check if a string is a policy instruction sentence
  static bool _isInstructionSentence(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final upper = trimmed.toUpperCase();

    // Headers and keywords
    if (upper.contains('INSTRUCTION') ||
        upper.contains('SERVICE INSTRUCTION') ||
        upper.contains('RULES AND REGULATION') ||
        upper.contains('TERMS AND CONDITION') ||
        upper.contains('CATERER GUIDELINE') ||
        upper.contains('MESS COMMITTEE') ||
        upper.contains('FOOD COMMITTEE') ||
        upper.contains('PENALTY') ||
        upper.contains('FEEDBACK') ||
        upper.contains('COMPLAINT') ||
        upper.startsWith('NOTE:') ||
        upper.startsWith('NOTE -') ||
        upper.startsWith('NOTE :') ||
        upper.startsWith('NOTICE:') ||
        upper.startsWith('IMPORTANT:') ||
        upper.startsWith('RULES:')) {
      return true;
    }

    // Common policy phrases in mess contracts
    final policyPhrases = [
      'MUST BE SERVED',
      'SHOULD BE SERVED',
      'SHALL BE SERVED',
      'MUST BE COOKED',
      'SHOULD BE COOKED',
      'MUST BE PROVIDED',
      'SHOULD BE PROVIDED',
      'SHALL BE PROVIDED',
      'TO BE SERVED',
      'TO BE PROVIDED',
      'AS PER THE MENU',
      'WEIGHING MACHINE',
      'FUNCTIONALLY AVAILABLE',
      'KEPT FUNCTIONAL',
      'SHOULD WEIGH',
      'MUST WEIGH',
      'SHALL WEIGH',
      'BEFORE SERVING',
      'AFTER COOKING',
      'WEIGHT AND GRAVY',
      'PREPARED USING',
      'GOOD-QUALITY',
      'GOOD QUALITY',
      'HIGHEST QUALITY',
      'STANDARD-SIZED',
      'MINIMAL WATER',
      'SHOULD BE KEPT',
      'MUST BE KEPT',
      'BY THE CATERER',
      'NOT BE FROZEN DESSERT',
      'STANDARD BRAND',
      'QUALITY OF FOOD',
      'STRICTLY PROHIBITED',
      'UNLIMITED EXCEPT',
      'PER STUDENT',
      'MESS TIMING',
      'BREAKFAST TIMING',
      'LUNCH TIMING',
      'DINNER TIMING',
      'SNACKS TIMING',
      'FOOD WASTE',
      'NOT EXCEED',
      'CLEANLINESS',
      'DISPOSABLE',
      'CATERING SUPERVISOR',
      'KITCHEN HYGIENE',
      'FSSAI',
      'VENDOR SHALL',
      'CATERER SHALL',
      'STUDENTS ARE REQUESTED',
      'STUDENTS MUST',
      'STUDENTS SHOULD',
      'ENTRY ALLOWED',
      'MESS CARD',
      'FINE WILL BE LEVIED',
      'FINE OF RS',
      'SONA MASURI',
      'GRAVY-BASED',
    ];

    for (final phrase in policyPhrases) {
      if (upper.contains(phrase)) return true;
    }

    // Long descriptive rule sentence check
    if (trimmed.length > 60 &&
        (upper.contains(' SHOULD ') ||
         upper.contains(' MUST ') ||
         upper.contains(' SHALL ') ||
         upper.contains(' WILL ') ||
         upper.contains(' EVERY DAY') ||
         upper.contains(' EVERYDAY'))) {
      return true;
    }

    return false;
  }

  /// Split multi-line cell text into food items while filtering out instruction lines and duplicates
  static List<String> _splitItems(String cell) {
    if (cell.trim().isEmpty) return [];

    final rawLines = cell.split(RegExp(r'[\n\r;]+'));
    final items = <String>[];

    for (String line in rawLines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (_isInstructionSentence(line)) continue;

      // Clean leading item numbers like "1. ", "2) ", "(1) ", "• ", "- ", "* " without stripping quantities like "2 Pcs Dosa"
      String cleaned = line
          .replaceAll(RegExp(r'^(?:\(\d+\)\s*|[\•\-\*]+\s*|\d+[\.\)\:]\s*)'), '')
          .trim();

      if (cleaned.isNotEmpty && !_isInstructionSentence(cleaned)) {
        items.add(cleaned);
      }
    }

    // Deduplicate preserving order
    final seen = <String>{};
    final uniqueItems = <String>[];
    for (final it in items) {
      if (seen.add(it.toLowerCase())) {
        uniqueItems.add(it);
      }
    }

    return uniqueItems;
  }

  static String _normalizeDayName(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.isEmpty) return '';
    if (RegExp(r'\bmon(?:day)?\b').hasMatch(lower)) return 'Mon';
    if (RegExp(r'\btue(?:s(?:day)?)?\b').hasMatch(lower)) return 'Tue';
    if (RegExp(r'\bwed(?:nes(?:day)?)?\b').hasMatch(lower)) return 'Wed';
    if (RegExp(r'\bthu(?:rs(?:day)?)?\b').hasMatch(lower)) return 'Thu';
    if (RegExp(r'\bfri(?:day)?\b').hasMatch(lower)) return 'Fri';
    if (RegExp(r'\bsat(?:urday)?\b').hasMatch(lower)) return 'Sat';
    if (RegExp(r'\bsun(?:day)?\b').hasMatch(lower)) return 'Sun';
    return '';
  }

  /// Extract date numbers from string (e.g. "Sat 1, 15, 29", "1 - 7", "22nd to 28th", "24/11/2026")
  static List<int> _extractDates(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return [];

    final dates = <int>{};

    // 1. Range regex: e.g. "1-7", "1 - 7", "1 to 7", "22 - 28", "22nd to 28th", "1st - 7th"
    final rangeRegex = RegExp(
      r'(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|to|–|—)\s*(\d{1,2})(?:st|nd|rd|th)?',
      caseSensitive: false,
    );
    for (final match in rangeRegex.allMatches(trimmed)) {
      final start = int.tryParse(match.group(1) ?? '');
      final end = int.tryParse(match.group(2) ?? '');
      if (start != null && end != null && start >= 1 && end <= 31 && start <= end && (end - start) <= 10) {
        for (int i = start; i <= end; i++) {
          dates.add(i);
        }
      }
    }

    // 2. Full dates: e.g. "24/11/2026", "24-11-2026", "24.11.2026"
    final fullDateRegex = RegExp(r'\b(\d{1,2})[\/\.-](\d{1,2})[\/\.-](\d{2,4})\b');
    for (final match in fullDateRegex.allMatches(trimmed)) {
      final day = int.tryParse(match.group(1) ?? '');
      if (day != null && day >= 1 && day <= 31) {
        dates.add(day);
      }
    }

    // Strip full dates, 4-digit years, and labels like "Week-1" / "Cycle 2" before checking standalone numbers
    String sanitized = trimmed.replaceAll(fullDateRegex, ' ');
    sanitized = sanitized.replaceAll(RegExp(r'\b20\d{2}\b'), ' ');
    sanitized = sanitized.replaceAll(RegExp(r'\b(?:week|cycle|phase)\s*[-:]?\s*\d+\b', caseSensitive: false), ' ');

    // 3. Standalone date numbers: e.g. "(3, 17)", "3, 17, 31", "10, 24", "3 & 17"
    final numMatches = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\b', caseSensitive: false).allMatches(sanitized);
    for (final m in numMatches) {
      final val = int.tryParse(m.group(1) ?? '');
      if (val != null && val >= 1 && val <= 31) {
        dates.add(val);
      }
    }

    final sorted = dates.toList()..sort();
    return sorted;
  }

  // ── Default VIT-AP Sample Menu ──

  static Map<String, Map<String, List<String>>> getDefaultSpecialMenu() {
    return {
      'Sat': {
        'Breakfast': [
          'Masala Ghee Roast Dosa', 'Vada Pav', 'Groundnut Chutney', 'Mint Chutney',
          'White Bread+Butter+Jam', 'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Guava Fresh Juice', 'Chocos', 'Scrambled Egg (Non-Veg)', 'Sweet Potato Salad (Veg)',
        ],
        'Lunch': [
          'Carrot & Cucumber Salad', 'Pulka', 'White Rice', 'Mudda Pappu',
          'Beetroot Tomato Rasam', 'Pulihora (Tamarind Rice)', 'Majiga Pulusu',
          'Chole Soya Chunks Curry', 'Papad', 'Lemon Water',
          'Avakaya (Mango Pickle)', 'Carrot Halwa',
        ],
        'Snacks': [
          'Punugulu 10 Pcs Std Size', 'Groundnut/Coconut Chutney', 'Ginger Tea/Coffee/Milk',
        ],
        'Dinner': [
          'Beetroot & Carrot Salad', 'Roti', 'White Rice', 'Mango Dal',
          'Bachali Kura Pulusu (Malabar Spinach)', 'Adai Dosa - 2 Pcs, Tomato Onion Chutney',
          'Cabbage Beans Poriyal', 'Tomato Baingan Masala', 'Thick Curd',
          'Muskmelon Cut Fruit', 'Red Chilli Pickle', 'Milk + Coffee Powder', 'Red Lentil Soup',
        ],
      },
      'Sun': {
        'Breakfast': [
          'Shavige Bath', 'Paneer Paratha - 2 Pcs Thin', 'Coconut Chutney',
          'Thick Curd, Mango Pickle', 'Brown Bread+Peanut Butter+Jam',
          'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Apple Fresh Juice', 'Cornflakes', 'Egg Bhurji (Non-Veg)', 'Raagi Malt',
        ],
        'Lunch': [
          'Beetroot & Cucumber Salad', 'Chapathi', 'White Rice', 'Dal', 'Sambar',
          'Chicken Dum Biryani/Paneer Dum Biryani',
          'Chicken Thick Gravy / Hyderabadi Mirchi Ka Salan',
          'Onion Raitha', 'Fryums', 'Nannari Sharbath',
          'Fresh Gongura Chutney', 'Vanilla Ice Cream (Made with Milk)', 'Gulab Jamun',
        ],
        'Snacks': [
          'Dahi Puri (8 Pcs)', 'Onions', 'Masala Tea/Coffee/Milk',
        ],
        'Dinner': [
          'Beetroot & Carrot Salad', 'Pulka', 'White Rice', 'Red Lentil Dal', 'Rasam',
          'Ragi Idly, Groundnut Chutney', 'Dondakaya Fry',
          'Vegetable Kurma Gravy', 'Thick Curd', 'Papaya Cut Fruit',
          'Tomato Pickle', 'Milk + Coffee Powder', 'Lemon Coriander Soup',
        ],
      },
      'Mon': {
        'Breakfast': [
          'Carrot Idly', 'Bhature - 2 Pcs Big', 'Groundnut Chutney', 'Chole Curry',
          'Brown Bread+Peanut Butter+Jam', 'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Banana Milk Shake', 'Cornflakes', 'Egg Bhurji (Non-Veg)', 'Paneer Bhurji (Veg)',
        ],
        'Lunch': [
          'Beetroot & Cucumber Salad', 'Chapathi', 'White Rice', 'Palak Dal', 'Sambar',
          'Tomato Rice', 'Pesara Punugulu Curry (Pakka Andhra Style)',
          'Drumstick Tomato Masala', 'Rava Vadiyalu', 'Butter Milk',
          'Sorakaya Perugu Chutney, Ghee + Podi', 'Jilebi',
        ],
        'Snacks': ['Dry Maggi', 'Tomato Sauce', 'Masala Tea/Coffee/Milk'],
        'Dinner': [
          'Onions & Lemon Salad', 'Methi Butter Roti', 'White Rice',
          'Pesara Pappu', 'Tomato Rasam', 'Bhagara Rice',
          'Telangana Chicken Curry (Non-Veg)', 'Achari Paneer (Veg)',
          'Ladies Finger Boiled Fry', 'Thick Curd', 'Mixed Fruit Salad',
          'Gongura Pickle', 'Milk + Coffee Powder', 'Sweet Corn Soup',
        ],
      },
      'Tue': {
        'Breakfast': [
          'Multi Grain Dosa (2 Pcs Thin)', 'Pav Bhaji', 'Coconut Chutney',
          'Mint Chutney', 'White Bread+Butter+Jam',
          'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Pomegranate Fresh Juice', 'Museli',
          'Scrambled Egg (Non-Veg)', 'Boiled Soya Chunk Salad (Veg)',
        ],
        'Lunch': [
          'Carrot & Cucumber Salad', 'Roti', 'White Rice',
          'Amaranthus Dal', 'Beetroot Tomato Rasam', 'Bisbele Bath',
          'Kakarakaya (Bitter Gourd) Fry', 'Rajma Masala',
          'Potato Chips', 'Dahi Vada', 'Dosakaya Tomato Chutney', 'Rasamalai',
        ],
        'Snacks': ['Aloo Samosa 1 Big Pc', 'Tomato Sauce', 'Ginger Tea/Coffee/Milk'],
        'Dinner': [
          'Beetroot & Carrot Salad', 'Pulka', 'White Rice',
          'Dal Makhani', 'Sambar', 'Mushroom Biryani',
          'Snake Gourd Poriyal', 'Aloo Mutter Curry', 'Thick Curd',
          'Guava Fruit', 'Tomato Pickle', 'Milk + Coffee Powder', 'Broccoli Soup',
        ],
      },
      'Wed': {
        'Breakfast': [
          'Methu Vada (Big size 3pcs, if not 4pcs)', 'Vegetable Dalia',
          'Sambar', 'Coconut Chutney', 'Brown Bread+Peanut Butter+Jam',
          'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Muskmelon Fresh Juice', 'Cornflakes',
          'Boiled Egg (Non-Veg)', 'Boiled Chick Peas Salad (Veg)',
        ],
        'Lunch': [
          'Onions & Lemon Salad', 'Palak Roti', 'White Rice',
          'Gongura (Sorrel Leaves) Dal', 'Sambar', 'Vegetable Dum Pulav',
          'Masala Fish Fry', 'Kaju Tomato Paneer Boiled Fry',
        ],
        'Snacks': ['Corn Vada', 'Onion Tomato Chutney', 'Masala Tea/Coffee/Milk'],
        'Dinner': [
          'Beetroot & Carrot Salad', 'Chapathi', 'White Rice',
          'Tomato Dal', 'Rasam', 'Sooji Upma, Coconut Chutney',
          'Carrot Beans Poriyal', 'Soya Chunks Masala', 'Thick Curd',
        ],
      },
      'Thu': {
        'Breakfast': [
          'Pongal', 'Poori - 3 Pcs', 'Coconut Chutney', 'Aloo Curry',
          'White Bread+Butter+Jam', 'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Orange Fresh Juice', 'Chocos', 'Omelette (Non-Veg)', 'Upma (Veg)',
        ],
        'Lunch': [
          'Carrot & Cucumber Salad', 'Pulka', 'White Rice',
          'Toor Dal', 'Rasam', 'Jeera Rice',
          'Paneer Butter Masala', 'Beans Poriyal',
          'Pappad', 'Butter Milk', 'Lemon Pickle', 'Kheer',
        ],
        'Snacks': ['Onion Pakoda', 'Tomato Ketchup', 'Ginger Tea/Coffee/Milk'],
        'Dinner': [
          'Onions & Lemon Salad', 'Roti', 'White Rice',
          'Mixed Dal', 'Sambar', 'Veg Fried Rice',
          'Chicken Curry (Non-Veg)', 'Kadai Paneer (Veg)',
          'Thick Curd', 'Watermelon Cut Fruit',
          'Red Chilli Pickle', 'Milk + Coffee Powder', 'Tomato Soup',
        ],
      },
      'Fri': {
        'Breakfast': [
          'Uggani + Mirchi Bajji', 'Basin Chilla (2 Pcs thin)',
          'Coconut Chutney', 'Tomato Chutney',
          'White Bread+Butter+Jam', 'Sprouts (1 small cup)', 'Tea/Coffee/Milk',
          'Pineapple Fresh Juice', 'Chocos',
          'Boiled Egg (Non-Veg)', 'Boiled Chick Peas Salad (Veg)',
        ],
        'Lunch': [
          'Beetroot & Cucumber Salad', 'Chapathi', 'White Rice',
          'Dal Tadka', 'Rasam', 'Jeera Rice', 'Raw Banana Fry',
          'Lobia Masala (Cowpeas in Onion Tomato Gravy)',
          'Papad', 'Lassi', 'Beerakaya Chutney', 'Poornalu',
        ],
        'Snacks': ['Onion Soft Pakoda', 'Tomato Chutney', 'Ginger Tea/Coffee/Milk'],
        'Dinner': [
          'Onions & Lemon Salad', 'Butter Naan', 'White Rice',
          'Dal', 'Sambar', 'Masala Fish Curry',
          'Paneer Tikka (Veg)', 'Vegetable Kolhapuri', 'Thick Curd',
          'Grapes', 'Fresh Vegetable Chutney/Pickle', 'Milk + Coffee Powder', 'Mix Veg Raagi Soup',
        ],
      },
    };
  }

  static Map<String, Map<String, List<String>>> getDefaultVegNonVegMenu() {
    return {
      'Mon': {
        'Breakfast': ['Idly - 4 Pcs', 'Peanut Chutney', 'Sambar', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Boiled Egg (Non-Veg)', 'Cornflakes'],
        'Lunch': ['Rice', 'Roti - 2 Pcs', 'Dal Fry', 'Sambar', 'Rasam', 'Mixed Veg Curry', 'Cabbage Poriyal', 'Curd', 'Pickle'],
        'Snacks': ['Veg Puff', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Chapathi - 2 Pcs', 'Dal', 'Rasam', 'Egg Curry (Non-Veg)', 'Paneer Curry (Veg)', 'Beans Fry', 'Curd', 'Pickle'],
      },
      'Tue': {
        'Breakfast': ['Dosa - 2 Pcs', 'Coconut Chutney', 'Sambar', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Egg Bhurji (Non-Veg)'],
        'Lunch': ['Rice', 'Pulka - 2 Pcs', 'Toor Dal', 'Sambar', 'Tomato Rasam', 'Aloo Gobi', 'Carrot Poriyal', 'Curd', 'Mango Pickle'],
        'Snacks': ['Samosa - 2 Pcs', 'Tomato Sauce', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Roti - 2 Pcs', 'Mixed Dal', 'Rasam', 'Chicken Curry (Non-Veg)', 'Mushroom Curry (Veg)', 'Potato Fry', 'Curd', 'Pickle'],
      },
      'Wed': {
        'Breakfast': ['Poori - 3 Pcs', 'Aloo Curry', 'Coconut Chutney', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Boiled Egg (Non-Veg)'],
        'Lunch': ['Rice', 'Chapathi - 2 Pcs', 'Palak Dal', 'Sambar', 'Rasam', 'Rajma Masala', 'Beans Poriyal', 'Curd', 'Pickle'],
        'Snacks': ['Bread Pakoda', 'Tomato Sauce', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Pulka - 2 Pcs', 'Dal Tadka', 'Rasam', 'Fish Fry (Non-Veg)', 'Paneer Butter Masala (Veg)', 'Cabbage Fry', 'Curd', 'Pickle'],
      },
      'Thu': {
        'Breakfast': ['Upma', 'Vada - 2 Pcs', 'Coconut Chutney', 'Sambar', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Omelette (Non-Veg)'],
        'Lunch': ['Rice', 'Roti - 2 Pcs', 'Moong Dal', 'Sambar', 'Rasam', 'Chole Masala', 'Snake Gourd Fry', 'Curd', 'Pickle'],
        'Snacks': ['Bajji - 4 Pcs', 'Peanut Chutney', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Chapathi - 2 Pcs', 'Dal', 'Rasam', 'Egg Masala (Non-Veg)', 'Soya Chunks Curry (Veg)', 'Beetroot Fry', 'Curd', 'Pickle'],
      },
      'Fri': {
        'Breakfast': ['Pongal', 'Coconut Chutney', 'Sambar', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Boiled Egg (Non-Veg)'],
        'Lunch': ['Rice', 'Pulka - 2 Pcs', 'Tomato Dal', 'Sambar', 'Rasam', 'Aloo Mutter', 'Ladies Finger Fry', 'Curd', 'Pickle', 'Papad'],
        'Snacks': ['Onion Pakoda', 'Tomato Sauce', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Roti - 2 Pcs', 'Dal Fry', 'Rasam', 'Chicken Biryani (Non-Veg)', 'Veg Biryani (Veg)', 'Raita', 'Curd', 'Pickle'],
      },
      'Sat': {
        'Breakfast': ['Rava Dosa - 2 Pcs', 'Groundnut Chutney', 'Sambar', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Egg Bhurji (Non-Veg)'],
        'Lunch': ['Rice', 'Chapathi - 2 Pcs', 'Yellow Dal', 'Sambar', 'Rasam', 'Mixed Veg Curry', 'Carrot Beans Poriyal', 'Curd', 'Pickle'],
        'Snacks': ['Punugulu - 8 Pcs', 'Peanut Chutney', 'Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Pulka - 2 Pcs', 'Dal', 'Rasam', 'Egg Curry (Non-Veg)', 'Kadai Paneer (Veg)', 'Capsicum Fry', 'Curd', 'Pickle'],
      },
      'Sun': {
        'Breakfast': ['Chole Bhature - 2 Pcs', 'Coconut Chutney', 'White Bread+Butter+Jam', 'Tea/Coffee/Milk', 'Boiled Egg (Non-Veg)', 'Cornflakes'],
        'Lunch': ['Rice', 'Roti - 2 Pcs', 'Dal', 'Sambar', 'Rasam', 'Chicken Biryani (Non-Veg)', 'Paneer Biryani (Veg)', 'Raita', 'Curd', 'Pickle', 'Gulab Jamun'],
        'Snacks': ['Dahi Puri', 'Masala Tea/Coffee/Milk'],
        'Dinner': ['Rice', 'Chapathi - 2 Pcs', 'Red Lentil Dal', 'Rasam', 'Egg Masala (Non-Veg)', 'Aloo Gobi (Veg)', 'Cabbage Poriyal', 'Curd', 'Pickle'],
      },
    };
  }

  static Future<void> loadDefaultMenus() async {
    await saveMenu('special', getDefaultSpecialMenu());
    await saveMenu('veg_nonveg', getDefaultVegNonVegMenu());
  }
}
