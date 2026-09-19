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
              menu[day]![meal] = itemsObj.map((e) => e.toString()).toList();
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

  // ── Retrieval ──

  /// Get menu for a day name or specific date number (e.g. dateNum = 8 for 8th of the month)
  static Future<Map<String, List<String>>> getMenuForDayOrDate(
    String messType, {
    required String dayName,
    int? dateNum,
  }) async {
    final menu = await loadMenu(messType);
    
    // 1. Try date-specific key first (e.g. Date_8)
    if (dateNum != null) {
      final dateKey = 'Date_$dateNum';
      if (menu.containsKey(dateKey)) {
        final dateMenu = menu[dateKey]!;
        bool hasItems = dateMenu.values.any((list) => list.isNotEmpty);
        if (hasItems) {
          return dateMenu;
        }
      }
    }

    // 2. Fall back to day name (e.g. 'Sat')
    if (menu.containsKey(dayName)) {
      final dayMenu = menu[dayName]!;
      bool hasItems = dayMenu.values.any((list) => list.isNotEmpty);
      if (hasItems) {
        return dayMenu;
      }
    }

    // 3. Fall back to case-insensitive match
    for (final key in menu.keys) {
      if (key.toLowerCase().startsWith(dayName.toLowerCase())) {
        final m = menu[key]!;
        if (m.values.any((list) => list.isNotEmpty)) {
          return m;
        }
      }
    }

    return {};
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

  /// Parse entire Excel workbook into mess types (e.g. 'veg_nonveg' -> menu, 'special' -> menu).
  /// Reads all sheets in the Excel workbook.
  static Map<String, Map<String, Map<String, List<String>>>> parseExcelWorkbook(List<int> bytes) {
    final result = <String, Map<String, Map<String, List<String>>>>{};
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return result;

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        final sheetMenu = parseSingleSheet(sheet);
        if (sheetMenu.isEmpty) continue;

        final lowerSheet = sheetName.toLowerCase();
        if (lowerSheet.contains('special')) {
          result['special'] = sheetMenu;
        } else if (lowerSheet.contains('veg') || lowerSheet.contains('non') || lowerSheet.contains('regular') || lowerSheet.contains('general') || lowerSheet.contains('normal')) {
          result['veg_nonveg'] = sheetMenu;
        } else {
          if (!result.containsKey('veg_nonveg')) {
            result['veg_nonveg'] = sheetMenu;
          } else if (!result.containsKey('special')) {
            result['special'] = sheetMenu;
          }
        }
      }

      // If only 1 sheet was parsed from the workbook, duplicate to both keys so user can view in either tab
      if (result.length == 1) {
        final existingKey = result.keys.first;
        final otherKey = existingKey == 'special' ? 'veg_nonveg' : 'special';
        result[otherKey] = result[existingKey]!;
      }
    } catch (e) {
      print('[MessMenu] Excel workbook parse error: $e');
    }
    return result;
  }

  /// Parse a single Excel sheet into a date-aware weekly/monthly menu
  static Map<String, Map<String, List<String>>> parseSingleSheet(xl.Sheet sheet) {
    final menu = <String, Map<String, List<String>>>{};
    try {
      int headerRow = -1;
      int dayCol = -1;
      int breakfastCol = -1;
      int lunchCol = -1;
      int snacksCol = -1;
      int dinnerCol = -1;

      for (int r = 0; r < sheet.maxRows && r < 15; r++) {
        for (int c = 0; c < sheet.maxColumns; c++) {
          final val = _cellValue(sheet, r, c).toLowerCase();
          if (val.contains('day')) dayCol = c;
          if (val.contains('breakfast')) breakfastCol = c;
          if (val.contains('lunch')) lunchCol = c;
          if (val.contains('snack')) snacksCol = c;
          if (val.contains('dinner')) dinnerCol = c;
        }
        if (dayCol >= 0 && breakfastCol >= 0) {
          headerRow = r;
          break;
        }
        dayCol = -1;
        breakfastCol = -1;
        lunchCol = -1;
        snacksCol = -1;
        dinnerCol = -1;
      }

      if (headerRow < 0) {
        for (int r = 0; r < sheet.maxRows && r < 15; r++) {
          for (int c = 0; c < sheet.maxColumns; c++) {
            final val = _cellValue(sheet, r, c).toLowerCase();
            if (val.contains('breakfast')) {
              breakfastCol = c;
              dayCol = c > 0 ? c - 1 : 0;
              headerRow = r;
              break;
            }
          }
          if (headerRow >= 0) break;
        }
      }

      if (headerRow < 0) return menu;

      if (breakfastCol < 0) breakfastCol = dayCol + 1;
      if (lunchCol < 0) lunchCol = breakfastCol + 1;
      if (snacksCol < 0) snacksCol = lunchCol + 1;
      if (dinnerCol < 0) dinnerCol = snacksCol + 1;

      String currentDayName = '';
      List<int> currentDates = [];

      for (int r = headerRow + 1; r < sheet.maxRows; r++) {
        final dayCell = _cellValue(sheet, r, dayCol).trim();
        final upperCell = dayCell.toUpperCase();

        // Only stop if explicitly hitting MESS SERVICE INSTRUCTIONS header row
        if (upperCell.contains('MESS SERVICE INSTRUCTIONS') || upperCell.contains('SERVICE INSTRUCTIONS')) {
          break;
        }

        if (dayCell.isNotEmpty) {
          final normalized = _normalizeDayName(dayCell);
          if (normalized.isNotEmpty) {
            currentDayName = normalized;
            currentDates = _extractDates(dayCell);
          }
        }
        if (currentDayName.isEmpty) continue;

        final breakfast = _splitItems(_cellValue(sheet, r, breakfastCol));
        final lunch = _splitItems(_cellValue(sheet, r, lunchCol));
        final snacks = _splitItems(_cellValue(sheet, r, snacksCol));
        final dinner = _splitItems(_cellValue(sheet, r, dinnerCol));

        if (breakfast.isEmpty && lunch.isEmpty && snacks.isEmpty && dinner.isEmpty) continue;

        final mealData = {
          'Breakfast': breakfast,
          'Lunch': lunch,
          'Snacks': snacks,
          'Dinner': dinner,
        };

        // 1. Store by specific date numbers if extracted (e.g. Date_1, Date_8, Date_15, Date_29)
        if (currentDates.isNotEmpty) {
          for (int dateNum in currentDates) {
            if (menu['Date_$dateNum'] == null) {
              menu['Date_$dateNum'] = {
                'Breakfast': List.from(breakfast),
                'Lunch': List.from(lunch),
                'Snacks': List.from(snacks),
                'Dinner': List.from(dinner),
              };
            } else {
              menu['Date_$dateNum']!['Breakfast']!.addAll(breakfast);
              menu['Date_$dateNum']!['Lunch']!.addAll(lunch);
              menu['Date_$dateNum']!['Snacks']!.addAll(snacks);
              menu['Date_$dateNum']!['Dinner']!.addAll(dinner);
            }
          }
        }

        // 2. Also store under day name fallback ('Sat', 'Sun', etc.)
        if (menu[currentDayName] == null) {
          menu[currentDayName] = {
            'Breakfast': List.from(breakfast),
            'Lunch': List.from(lunch),
            'Snacks': List.from(snacks),
            'Dinner': List.from(dinner),
          };
        } else {
          menu[currentDayName]!['Breakfast']!.addAll(breakfast);
          menu[currentDayName]!['Lunch']!.addAll(lunch);
          menu[currentDayName]!['Snacks']!.addAll(snacks);
          menu[currentDayName]!['Dinner']!.addAll(dinner);
        }
      }
    } catch (e) {
      print('[MessMenu] Single sheet parse error: $e');
    }
    return menu;
  }

  static String _cellValue(xl.Sheet sheet, int row, int col) {
    if (row >= sheet.maxRows || col >= sheet.maxColumns || col < 0) return '';
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    return cell.value?.toString() ?? '';
  }

  /// Parse CSV text into a date-aware menu
  static Map<String, Map<String, List<String>>> parseCsvText(String csvText) {
    final menu = <String, Map<String, List<String>>>{};
    final lines = csvText.split('\n');
    
    int headerIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (lower.contains('day') && lower.contains('breakfast')) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx == -1 && lines.length > 1) headerIdx = 0;
    if (headerIdx == -1) return menu;

    String currentDayName = '';
    List<int> currentDates = [];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final upperLine = line.toUpperCase();
      if (upperLine.contains('MESS SERVICE INSTRUCTIONS') || upperLine.contains('SERVICE INSTRUCTIONS')) {
        break;
      }

      final cells = _splitCsvLine(line);
      if (cells.length < 5) continue;

      final dayCell = cells[0].trim();
      if (dayCell.isNotEmpty) {
        final normalized = _normalizeDayName(dayCell);
        if (normalized.isNotEmpty) {
          currentDayName = normalized;
          currentDates = _extractDates(dayCell);
        }
      }
      if (currentDayName.isEmpty) continue;

      final mealData = {
        'Breakfast': _splitItems(cells[1]),
        'Lunch': _splitItems(cells[2]),
        'Snacks': _splitItems(cells[3]),
        'Dinner': _splitItems(cells[4]),
      };

      if (currentDates.isNotEmpty) {
        for (int dateNum in currentDates) {
          menu['Date_$dateNum'] = mealData;
        }
      }
      if (menu[currentDayName] == null) {
        menu[currentDayName] = mealData;
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

  /// Check if a string is a policy instruction sentence
  static bool _isInstructionSentence(String text) {
    final upper = text.toUpperCase().trim();
    if (upper.isEmpty) return false;

    if (upper.contains('MESS SERVICE INSTRUCTIONS') ||
        upper.contains('SERVICE INSTRUCTIONS') ||
        upper.startsWith('INSTRUCTION')) {
      return true;
    }

    if (upper.contains('MUST BE SERVED') ||
        upper.contains('WEIGHING MACHINE') ||
        upper.contains('FUNCTIONALLY AVAILABLE') ||
        upper.contains('SHOULD WEIGH') ||
        upper.contains('PREPARED USING') ||
        upper.contains('SHOULD BE KEPT') ||
        upper.contains('DEPENDING ON THE SIZE SERVED') ||
        upper.contains('BY THE CATERER') ||
        upper.contains('NOT BE FROZEN DESSERT')) {
      return true;
    }

    return false;
  }

  /// Split multi-line cell text into food items while filtering out instruction lines
  static List<String> _splitItems(String cell) {
    if (cell.trim().isEmpty) return [];

    final rawLines = cell.split(RegExp(r'[\n\r;]+'));
    final items = <String>[];

    for (String line in rawLines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Filter out policy instruction sentences
      if (_isInstructionSentence(line)) continue;

      // Clean leading item numbers like "1. ", "2. ", "1) ", "• ", "- "
      String cleaned = line.replaceAll(RegExp(r'^[\d\•\-\*]+[\.\)\:]*\s*'), '').trim();

      if (cleaned.isNotEmpty && !_isInstructionSentence(cleaned)) {
        items.add(cleaned);
      }
    }

    return items;
  }

  static String _normalizeDayName(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('mon')) return 'Mon';
    if (lower.contains('tue')) return 'Tue';
    if (lower.contains('wed')) return 'Wed';
    if (lower.contains('thu')) return 'Thu';
    if (lower.contains('fri')) return 'Fri';
    if (lower.contains('sat')) return 'Sat';
    if (lower.contains('sun')) return 'Sun';
    return '';
  }

  /// Extract date numbers from string (e.g. "Sat 1, 15, 29" -> [1, 15, 29])
  static List<int> _extractDates(String raw) {
    final matches = RegExp(r'\b\d+\b').allMatches(raw);
    final dates = <int>[];
    for (final m in matches) {
      final val = int.tryParse(m.group(0)!);
      if (val != null && val >= 1 && val <= 31) {
        dates.add(val);
      }
    }
    return dates;
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
