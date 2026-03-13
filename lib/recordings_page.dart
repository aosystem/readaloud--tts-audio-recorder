import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:readaloud/l10n/app_localizations.dart';
import 'package:readaloud/recording_manager.dart';
import "package:readaloud/ad_banner_widget.dart";
import "package:readaloud/ad_manager.dart";


class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  late AdManager _adManager;
  Future<List<Recording>>? _recordingsFuture;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<void>? _playerCompleteSubscription;
  String? _currentPath;
  bool _hasRequestedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    _adManager = AdManager();
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentPath = null;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasRequestedInitialLoad) {
      _recordingsFuture = _loadRecordings();
      _hasRequestedInitialLoad = true;
    }
  }

  Future<List<Recording>> _loadRecordings() {
    final manager = context.read<RecordingManager>();
    return manager.fetchRecordings();
  }

  Future<void> _reloadRecordings() async {
    final future = _loadRecordings();
    if (!mounted) {
      return;
    }
    setState(() {
      _recordingsFuture = future;
    });
    await future;
  }

  @override
  void dispose() {
    _adManager.dispose();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playRecording(Recording recording) async {
    if (_currentPath == recording.path) {
      await _audioPlayer.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentPath = null;
      });
      return;
    }
    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(recording.path));
    if (!mounted) {
      return;
    }
    setState(() {
      _currentPath = recording.path;
    });
  }

  Future<void> _shareRecording(Recording recording) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(recording.path)]));
  }

  Future<void> _deleteRecording(
    Recording recording,
    AppLocalizations l,
  ) async {
    final manager = context.read<RecordingManager>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.recordingDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _audioPlayer.stop();
    await manager.deleteRecording(recording.path);
    if (!mounted) {
      return;
    }
    if (_currentPath == recording.path) {
      _currentPath = null;
    }
    await _reloadRecordings();
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.recordingDeleted)));
  }

  String _formatDate(DateTime date) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formatter.format(date);
  }

  String _formatSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    if (bytes < 1024) {
      return '${bytes}B';
    }
    double size = bytes / 1024;
    var suffixIndex = 0;
    while (size >= 1024 && suffixIndex < suffixes.length - 2) {
      size /= 1024;
      suffixIndex++;
    }
    String formatted;
    if (size >= 100) {
      formatted = size.toStringAsFixed(0);
    } else if (size >= 10) {
      formatted = size.toStringAsFixed(1);
    } else {
      formatted = size.toStringAsFixed(2);
    }
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    final unit = suffixes[suffixIndex + 1];
    return '$formatted$unit';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final future = _recordingsFuture;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.recordings),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Recording>>(
        future: future,
        builder: (context, snapshot) {
          if (future == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _reloadRecordings,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      l.recordingsLoadError,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }
          final recordings = snapshot.data ?? <Recording>[];
          if (recordings.isEmpty) {
            return RefreshIndicator(
              onRefresh: _reloadRecordings,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Text(
                      l.recordingsEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reloadRecordings,
            child: ListView.separated(
              padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 100),
              itemCount: recordings.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final recording = recordings[index];
                final isPlaying = recording.path == _currentPath;
                return _RecordingCard(
                  recording: recording,
                  isPlaying: isPlaying,
                  dateLabel: _formatDate(recording.createdAt),
                  sizeLabel: _formatSize(recording.sizeBytes),
                  onPlay: () => _playRecording(recording),
                  onDelete: () => _deleteRecording(recording, l),
                  onShare: () => _shareRecording(recording),
                  l: l,
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: AdBannerWidget(adManager: _adManager),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.recording,
    required this.isPlaying,
    required this.dateLabel,
    required this.sizeLabel,
    required this.onPlay,
    required this.onDelete,
    required this.onShare,
    required this.l,
  });

  final Recording recording;
  final bool isPlaying;
  final String dateLabel;
  final String sizeLabel;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$dateLabel  $sizeLabel', style: theme.textTheme.titleMedium),
            const SizedBox(height: 1),
            Text(
              recording.fileName,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 14),
                  label: Text(isPlaying ? l.stop : l.play, style: TextStyle(fontSize: 11)),
                ),
                FilledButton.tonalIcon(
                  onPressed: onShare,
                  icon: const Icon(Icons.send, size: 14),
                  label: Text(l.send, style: TextStyle(fontSize: 11)),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.errorContainer,
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 14),
                  label: Text(l.delete, style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
