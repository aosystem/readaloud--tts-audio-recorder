import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Recording {
  const Recording({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
  });

  final File file;
  final DateTime createdAt;
  final int sizeBytes;

  String get path => file.path;
  String get fileName => p.basename(path);
}

class RecordingManager extends ChangeNotifier {
  RecordingManager();

  static const String _directoryName = 'recordings';

  final List<Recording> _recordings = <Recording>[];

  List<Recording> get recordings => List.unmodifiable(_recordings);

  Future<Directory> getRecordingDirectory() async {
    Directory? baseDirectory;
    if (Platform.isAndroid) {
      baseDirectory = await getExternalStorageDirectory();
    }
    baseDirectory ??= await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory(
      p.join(baseDirectory.path, _directoryName),
    );
    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }
    return recordingsDirectory;
  }

  Future<String> createFilePath() async {
    final directory = await getRecordingDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now());
    final fileName = 'record_$timestamp.wav';
    return p.join(directory.path, fileName);
  }

  Future<List<Recording>> fetchRecordings() async {
    await refreshRecordings();
    return recordings;
  }

  Future<void> refreshRecordings() async {
    final recordings = await _readRecordings();
    _recordings
      ..clear()
      ..addAll(recordings);
    notifyListeners();
  }

  Future<List<Recording>> _readRecordings() async {
    final directory = await getRecordingDirectory();
    final recordings = <Recording>[];
    if (!await directory.exists()) {
      return recordings;
    }
    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.wav') {
        continue;
      }
      final stat = await entity.stat();
      recordings.add(
        Recording(file: entity, createdAt: stat.modified, sizeBytes: stat.size),
      );
    }
    recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recordings;
  }

  Future<void> deleteRecording(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await refreshRecordings();
  }
}
