import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/note_model.dart';
import '../services/notes_service.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';

class NotesCalendarScreen extends StatefulWidget {
  final DateTime initialDate;
  
  const NotesCalendarScreen({Key? key, required this.initialDate}) : super(key: key);

  @override
  State<NotesCalendarScreen> createState() => _NotesCalendarScreenState();
}

class _NotesCalendarScreenState extends State<NotesCalendarScreen> {
  late DateTime _selectedDate;
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final notes = await NotesService.getNotesForDate(_selectedDate);
    if (mounted) {
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    }
  }

  void _onDateChanged(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _loadNotes();
  }

  void _showAddNoteDialog({Note? existingNote}) {
    final titleCtrl = TextEditingController(text: existingNote?.title ?? '');
    final descCtrl = TextEditingController(text: existingNote?.description ?? '');
    TimeOfDay? selectedTime = existingNote?.reminderTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        existingNote != null 
                            ? "Edit Note for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"
                            : "Add Note for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}", 
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        labelText: "Title",
                        labelStyle: TextStyle(color: AppColors.textMuted(context)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder(context)), borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary), borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        labelText: "Description (Optional)",
                        labelStyle: TextStyle(color: AppColors.textMuted(context)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.cardBorder(context)), borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary), borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedTime == null 
                                ? "No Reminder Set" 
                                : "Reminder: ${selectedTime!.format(context)}",
                            style: TextStyle(
                              color: selectedTime == null ? AppColors.textMuted(context) : AppColors.primary,
                              fontWeight: selectedTime == null ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context, 
                              initialTime: TimeOfDay.now()
                            );
                            if (t != null) {
                              setSheetState(() => selectedTime = t);
                            }
                          },
                          icon: const Icon(Icons.alarm_add),
                          label: const Text("Set Time"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          
                          final note = Note(
                            id: existingNote?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                            title: titleCtrl.text.trim(),
                            description: descCtrl.text.trim(),
                            date: _selectedDate,
                            reminderTime: selectedTime,
                            createdAt: existingNote?.createdAt ?? DateTime.now(),
                          );
                          
                          await NotificationService.instance.cancelNoteReminder(note.id);
                          await NotesService.saveNote(note);
                          await NotificationService.instance.scheduleNoteReminder(note);
                          
                          if (mounted) {
                            Navigator.pop(ctx);
                            _loadNotes();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(existingNote != null ? "Update Note" : "Save Note", style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  void _deleteNoteConfirm(Note note) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text("Delete Note", style: TextStyle(color: AppColors.textPrimary(context))),
        content: Text("Are you sure you want to delete this note?", style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              NotesService.deleteNote(note.id, note.date).then((_) {
                NotificationService.instance.cancelNoteReminder(note.id);
                _loadNotes();
              });
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.note_alt_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  if (note.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                  if (note.reminderTime != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.alarm, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          note.reminderTime!.format(context),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                  onPressed: () => _showAddNoteDialog(existingNote: note),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteNoteConfirm(note),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Calendar & Notes", style: TextStyle(color: AppColors.textPrimary(context))),
        iconTheme: IconThemeData(color: AppColors.textPrimary(context)),
        actions: [
          TextButton(
            onPressed: () {
              // Return the selected date to timetable
              Navigator.pop(context, _selectedDate);
            },
            child: Text("Jump to Date", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddNoteDialog(),
        icon: const Icon(Icons.add),
        label: const Text("Add Note"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.cardBg(context),
                  onSurface: AppColors.textPrimary(context),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
                onDateChanged: _onDateChanged,
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Text(
                  "Notes for ${_selectedDate.day}/${_selectedDate.month}",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Builder(
              builder: (context) {
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_notes.isEmpty) {
                  return Center(
                    child: Text(
                      "No notes for this date.", 
                      style: TextStyle(color: AppColors.textMuted(context))
                    )
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    return _buildNoteCard(_notes[index]);
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}
