import 'package:flutter/material.dart';
import 'dart:convert';

class Note {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final TimeOfDay? reminderTime;
  final DateTime createdAt;

  Note({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    this.reminderTime,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'reminderTime': reminderTime != null ? '${reminderTime!.hour}:${reminderTime!.minute}' : null,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    TimeOfDay? parsedTime;
    if (json['reminderTime'] != null) {
      final parts = json['reminderTime'].toString().split(':');
      if (parts.length == 2) {
        parsedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    }

    return Note(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      reminderTime: parsedTime,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
