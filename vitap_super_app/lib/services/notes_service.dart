import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_model.dart';

class NotesService {
  static const String _keyPrefix = 'notes_';

  /// Returns the key used for a specific date (yyyy-MM-dd)
  static String _getKeyForDate(DateTime date) {
    return '$_keyPrefix${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get all notes for a specific date
  static Future<List<Note>> getNotesForDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKeyForDate(date);
    final String? notesJson = prefs.getString(key);
    
    if (notesJson == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(notesJson);
      return decoded.map((e) => Note.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Error parsing notes for date $date: $e");
      return [];
    }
  }

  /// Save a note (adds it or updates if ID exists)
  static Future<void> saveNote(Note note) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKeyForDate(note.date);
    
    List<Note> notes = await getNotesForDate(note.date);
    
    final existingIndex = notes.indexWhere((n) => n.id == note.id);
    if (existingIndex >= 0) {
      notes[existingIndex] = note;
    } else {
      notes.add(note);
    }
    
    final encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(key, encoded);
  }

  /// Delete a note by its ID and Date
  static Future<void> deleteNote(String id, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKeyForDate(date);
    
    List<Note> notes = await getNotesForDate(date);
    notes.removeWhere((n) => n.id == id);
    
    if (notes.isEmpty) {
      await prefs.remove(key);
    } else {
      final encoded = jsonEncode(notes.map((n) => n.toJson()).toList());
      await prefs.setString(key, encoded);
    }
  }
}
