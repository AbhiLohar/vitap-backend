import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../widgets/glass_card.dart';
import '../services/mess_menu_service.dart';

class MessMenuScreen extends StatefulWidget {
  const MessMenuScreen({super.key});

  @override
  State<MessMenuScreen> createState() => _MessMenuScreenState();
}

class _MessMenuScreenState extends State<MessMenuScreen> {
  String _messType = 'special';
  
  late DateTime _today;
  late List<DateTime> _weekDays;
  late DateTime _selectedDate;

  Map<String, List<String>> _dayMenu = {};
  bool _isLoading = true;
  bool _isEditing = false;
  bool _hasMenu = false;

  // Pending menu uploaded via file (awaiting "Apply Changes")
  Map<String, Map<String, List<String>>>? _pendingParsedMenu;
  Map<String, Map<String, Map<String, List<String>>>>? _pendingAllSheets;
  String? _pendingFileName;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _buildWeekDays();
    _loadMenu();
  }

  void _buildWeekDays() {
    _today = DateTime.now();
    // Monday of current week
    final monday = _today.subtract(Duration(days: _today.weekday - 1));
    _weekDays = List.generate(7, (i) => monday.add(Duration(days: i))); // Mon-Sun
    _selectedDate = _today;
  }

  Future<void> _loadMenu() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final dayName = MessMenuService.dayOrder[_selectedDate.weekday - 1];
      final dateNum = _selectedDate.day;

      final menu = await MessMenuService.getMenuForDayOrDate(
        _messType,
        dayName: dayName,
        dateNum: dateNum,
      );
      
      if (mounted) {
        setState(() {
          _dayMenu = menu;
          _hasMenu = _dayMenu.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasMenu = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onDateChanged(DateTime date) {
    if (_selectedDate.year == date.year &&
        _selectedDate.month == date.month &&
        _selectedDate.day == date.day) {
      return;
    }
    setState(() {
      _selectedDate = date;
    });
    _loadMenu();
  }

  void _onMessTypeChanged(String type) {
    if (_messType == type) return;
    setState(() {
      _messType = type;
    });
    _loadMenu();
  }

  bool _isNonVeg(String item) {
    final lowerItem = item.toLowerCase();
    return lowerItem.contains('non-veg') ||
        lowerItem.contains('egg') ||
        lowerItem.contains('chicken') ||
        lowerItem.contains('fish') ||
        lowerItem.contains('mutton');
  }

  bool _isSpecial(String item) {
    final lowerItem = item.toLowerCase();
    return lowerItem.contains('juice') ||
        lowerItem.contains('ice cream') ||
        lowerItem.contains('halwa') ||
        lowerItem.contains('soup') ||
        lowerItem.contains('jilebi') ||
        lowerItem.contains('gulab') ||
        lowerItem.contains('rasamalai') ||
        lowerItem.contains('kheer') ||
        lowerItem.contains('poornalu');
  }

  /// Pick file (Excel or CSV), parse it, and show progress + preview
  Future<void> _pickAndParseFile(List<String> extensions) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isUploading = true);

      final file = result.files.single;
      List<int>? bytes = file.bytes;

      if ((bytes == null || bytes.isEmpty) && file.path != null && file.path!.isNotEmpty) {
        final f = File(file.path!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }

      Map<String, Map<String, Map<String, List<String>>>> allSheets = {};
      Map<String, Map<String, List<String>>> parsedSingle = {};

      if (file.name.toLowerCase().endsWith('.xlsx') || file.name.toLowerCase().endsWith('.xls')) {
        if (bytes != null && bytes.isNotEmpty) {
          allSheets = MessMenuService.parseExcelWorkbook(bytes);
        }
      } else if (file.name.toLowerCase().endsWith('.csv')) {
        String? text;
        if (bytes != null && bytes.isNotEmpty) {
          text = String.fromCharCodes(bytes);
        } else if (file.path != null && file.path!.isNotEmpty) {
          text = await File(file.path!).readAsString();
        }
        if (text != null && text.isNotEmpty) {
          parsedSingle = MessMenuService.parseCsvText(text);
          if (parsedSingle.isNotEmpty) {
            allSheets = {
              'veg_nonveg': parsedSingle,
              'special': parsedSingle,
            };
          }
        }
      }

      setState(() => _isUploading = false);

      if (allSheets.isEmpty && parsedSingle.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Could not parse menu file. Ensure it has columns: Day, Breakfast, Lunch, Snacks, Dinner.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Store pending parsed menu for preview & Apply Changes
      setState(() {
        _pendingAllSheets = allSheets.isNotEmpty ? allSheets : null;
        _pendingParsedMenu = parsedSingle.isNotEmpty ? parsedSingle : null;
        _pendingFileName = file.name;
      });

      final totalCount = allSheets.isNotEmpty 
          ? allSheets.values.first.keys.length 
          : parsedSingle.keys.length;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Picked "${file.name}" ($totalCount dates found). Tap "Apply Changes" to save!'),
            backgroundColor: AppColors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error reading file: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Apply pending parsed menu to storage
  Future<void> _applyPendingMenu() async {
    if (_pendingAllSheets == null && _pendingParsedMenu == null) return;
    setState(() => _isLoading = true);
    
    try {
      if (_pendingAllSheets != null && _pendingAllSheets!.isNotEmpty) {
        for (final entry in _pendingAllSheets!.entries) {
          await MessMenuService.saveMenu(entry.key, entry.value);
        }
      } else if (_pendingParsedMenu != null) {
        await MessMenuService.saveMenu(_messType, _pendingParsedMenu!);
        final otherType = _messType == 'special' ? 'veg_nonveg' : 'special';
        final hasOther = await MessMenuService.hasMenu(otherType);
        if (!hasOther) {
          await MessMenuService.saveMenu(otherType, _pendingParsedMenu!);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Mess menu updated & applied successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to save menu: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() {
        _pendingAllSheets = null;
        _pendingParsedMenu = null;
        _pendingFileName = null;
      });
      await _loadMenu();
    }
  }

  Future<void> _showEditDialog(String mealType, List<String> currentItems) async {
    final controller = TextEditingController(text: currentItems.join('\n'));
    final dayName = MessMenuService.dayOrder[_selectedDate.weekday - 1];
    final dateKey = 'Date_${_selectedDate.day}';
    final primary = Theme.of(context).colorScheme.primary;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.cardBg(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Edit $mealType',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
          ),
          content: TextField(
            controller: controller,
            maxLines: 8,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: 14,
            ),
            decoration: InputDecoration(
              hintText: 'Enter items, one per line',
              hintStyle: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
              filled: true,
              fillColor: AppColors.scaffoldBg(context),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.cardBorder(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primary, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary(context))),
            ),
            ElevatedButton(
              onPressed: () async {
                final newItems = controller.text
                    .split('\n')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                await MessMenuService.updateMealItems(
                    _messType, dateKey, mealType, newItems);
                await MessMenuService.updateMealItems(
                    _messType, dayName, mealType, newItems);
                if (mounted) {
                  Navigator.pop(context);
                  _loadMenu();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showUploadSheet() async {
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Upload Mess Menu File',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select your monthly mess menu file (.xlsx or .csv) from your device',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.cardBorder(context)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.table_chart_outlined, color: primary, size: 22),
                ),
                title: Text(
                  'Upload Excel (.xlsx)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  'Parses sheets with Day, Breakfast, Lunch, Snacks, Dinner',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndParseFile(['xlsx', 'xls']);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.cardBorder(context)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.good.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.text_snippet_outlined, color: AppColors.good, size: 22),
                ),
                title: Text(
                  'Upload CSV (.csv)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary(context)),
                ),
                subtitle: Text(
                  'Parses comma separated values menu file',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndParseFile(['csv']);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Mess Menu',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: _showUploadSheet,
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Change Menu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: _isEditing ? 'Done Editing' : 'Edit Items',
            icon: Icon(
              _isEditing ? Icons.check_circle_rounded : Icons.edit_outlined,
              color: _isEditing ? primary : AppColors.textPrimary(context),
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(child: CircularProgressIndicator(color: primary))
              : Column(
                  children: [
                    _buildMessTypeToggle(),
                    const SizedBox(height: 10),
                    
                    if (_pendingAllSheets != null || _pendingParsedMenu != null) _buildPendingPreviewBanner(),

                    if (_hasMenu && _pendingAllSheets == null && _pendingParsedMenu == null) _buildTopChangeHeader(),

                    const SizedBox(height: 6),
                    _buildDaySelector(),
                    const SizedBox(height: 10),

                    Expanded(
                      child: _hasMenu ? _buildMenuCards() : _buildEmptyState(),
                    ),
                  ],
                ),

          if (_isUploading)
            Container(
              color: Colors.black45,
              child: Center(
                child: GlassCard(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primary),
                      const SizedBox(height: 20),
                      Text(
                        'Reading & Parsing Menu...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Extracting dates and meal items',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPendingPreviewBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    final daysCount = _pendingAllSheets != null 
        ? _pendingAllSheets!.values.first.keys.length
        : (_pendingParsedMenu?.keys.length ?? 0);

    final sheetInfo = _pendingAllSheets != null && _pendingAllSheets!.length > 1
        ? 'Veg & Non-Veg Mess + Special Mess'
        : (_messType == 'special' ? 'Special Mess' : 'Veg & Non-Veg Mess');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.file_present_outlined, color: primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pendingFileName ?? 'Uploaded Menu File',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sheetInfo ($daysCount Dates Parsed)',
                      style: TextStyle(fontSize: 11, color: AppColors.good, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.good.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.good.withOpacity(0.3)),
                ),
                child: Text(
                  'Ready',
                  style: TextStyle(fontSize: 11, color: AppColors.good, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _applyPendingMenu,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Apply Changes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _pendingAllSheets = null;
                    _pendingParsedMenu = null;
                    _pendingFileName = null;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopChangeHeader() {
    final primary = Theme.of(context).colorScheme.primary;
    final title = _messType == 'special' ? 'Special Mess' : 'Veg & Non-Veg';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 14, color: AppColors.good),
              const SizedBox(width: 6),
              Text(
                '$title Menu Active',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary(context)),
              ),
            ],
          ),
          InkWell(
            onTap: _showUploadSheet,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.refresh_rounded, size: 14, color: primary),
                  const SizedBox(width: 4),
                  Text(
                    'Change Menu File',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessTypeToggle() {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _onMessTypeChanged('veg_nonveg'),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _messType == 'veg_nonveg' ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    'Veg & Non-Veg',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _messType == 'veg_nonveg' ? Colors.white : AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _onMessTypeChanged('special'),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _messType == 'special' ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    'Special Mess',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _messType == 'special' ? Colors.white : AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _weekDays.map((date) {
          final dayName = MessMenuService.dayOrder[date.weekday - 1];
          final isSelected = date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;
          final isToday = date.year == _today.year &&
              date.month == _today.month &&
              date.day == _today.day;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onDateChanged(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? primary : AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? primary
                        : (isToday ? AppColors.good : AppColors.cardBorder(context)),
                    width: isToday && !isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.white : AppColors.textSecondary(context),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected ? Colors.white : AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuCards() {
    final primary = Theme.of(context).colorScheme.primary;
    final meals = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'];
    final mealColors = {
      'Breakfast': AppColors.warning,
      'Lunch': AppColors.good,
      'Snacks': AppColors.purple,
      'Dinner': primary,
    };

    final currentMeal = MessMenuService.getUpcomingMealName();
    final isTodaySelected = _selectedDate.year == _today.year &&
        _selectedDate.month == _today.month &&
        _selectedDate.day == _today.day;

    return RefreshIndicator(
      onRefresh: _loadMenu,
      color: primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: meals.length,
        itemBuilder: (context, index) {
          final meal = meals[index];
          final items = _dayMenu[meal] ?? [];
          final isCurrent = (meal == currentMeal && isTodaySelected);

          return _buildMealCard(
            meal: meal,
            items: items,
            accentColor: mealColors[meal] ?? primary,
            isCurrent: isCurrent,
          );
        },
      ),
    );
  }

  Widget _buildMealCard({
    required String meal,
    required List<String> items,
    required Color accentColor,
    required bool isCurrent,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        accentColor: isCurrent ? primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        MessMenuService.mealEmoji[meal] ?? '🍽️',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meal,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          MessMenuService.mealTimeDisplay[meal] ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_isEditing)
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: primary, size: 18),
                    onPressed: () => _showEditDialog(meal, items),
                  )
                else if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primary.withOpacity(0.3)),
                    ),
                    child: Text(
                      'NOW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: primary,
                      ),
                    ),
                  ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: AppColors.cardBorder(context)),
              const SizedBox(height: 12),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isNonVeg(item) ? AppColors.danger : AppColors.good,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                              ),
                              if (_isSpecial(item)) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Special', style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'No items available for this meal.',
                style: TextStyle(
                  color: AppColors.textMuted(context),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant_menu_rounded,
                size: 44,
                color: primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Mess Menu Uploaded',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload your monthly mess menu file (.xlsx or .csv) from your device to view day-wise meals for Veg, Non-Veg, and Special mess.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showUploadSheet,
                icon: const Icon(Icons.upload_file, size: 20),
                label: const Text('Upload Mess Menu (Excel / CSV)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
