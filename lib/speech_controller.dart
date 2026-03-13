import "dart:io";
import "package:flutter/foundation.dart";
import "package:flutter_tts/flutter_tts.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

const String _systemDefaultVoiceId = '__system_default__';

enum SpeechEventType {
  beginSynthesis,
  audioAvailable,
  start,
  done,
  stop,
  error,
}

class SpeechEvent {
  const SpeechEvent(this.type, {this.errorMessage});

  final SpeechEventType type;
  final String? errorMessage;

  String get localizationKey {
    switch (type) {
      case SpeechEventType.beginSynthesis:
        return "ttsBeginSynthesis";
      case SpeechEventType.audioAvailable:
        return "ttsAudioAvailable";
      case SpeechEventType.start:
        return "ttsStart";
      case SpeechEventType.done:
        return "ttsDone";
      case SpeechEventType.stop:
        return "ttsStop";
      case SpeechEventType.error:
        return "ttsError";
    }
  }
}

class VoiceOption {
  const VoiceOption({
    required this.name,
    required this.locale,
    this.gender,
    this.isSystemDefault = false,
  });

  final String name;
  final String locale;
  final String? gender;
  final bool isSystemDefault;

  String get id => isSystemDefault ? _systemDefaultVoiceId : "$locale::$name";
  String get displayLabel {
    if (isSystemDefault) {
      return name;
    }
    final parts = <String>[
      locale,
      name,
    ].where((value) => value.isNotEmpty).toList();
    return parts.join(' ');
  }

  Map<String, String> toMap() => {"name": name, "locale": locale};
}

class SpeechController extends ChangeNotifier {
  SpeechController(this._prefs);

  static const VoiceOption defaultVoiceOption = VoiceOption(
    name: 'default',
    locale: '',
    isSystemDefault: true,
  );

  static const _voicePreferenceKey = "speechVoice";
  static const double _defaultBaseRate = 0.5;
  static const double _minRateFactor = 0.2;
  static const double _maxRateFactor = 3.0;
  static const double _defaultMinPitch = 0.2;
  static const double _defaultMaxPitch = 3.0;
  static const double _iosMinPitch = 0.5;
  static const double _iosMaxPitch = 2.0;

  final SharedPreferences _prefs;
  final FlutterTts _tts = FlutterTts();

  final List<VoiceOption> _voices = <VoiceOption>[];
  VoiceOption? _selectedVoice;
  double _baseRate = _defaultBaseRate;
  double _minRate = _defaultBaseRate * _minRateFactor;
  double _maxRate = _defaultBaseRate * _maxRateFactor;
  double _minPitch = _defaultMinPitch;
  double _maxPitch = _defaultMaxPitch;

  double _speed = _defaultBaseRate;
  double _pitch = 1.0;
  bool _isSpeaking = false;
  bool _initialized = false;
  SpeechEvent? _lastEvent;
  int _eventToken = 0;

  List<VoiceOption> get voices => List.unmodifiable(_voices);
  VoiceOption? get selectedVoice => _selectedVoice ?? defaultVoiceOption;
  double get speed => _speed;
  double get pitch => _pitch;
  double get baseRate => _baseRate;
  double get minRate => _minRate;
  double get maxRate => _maxRate;
  double get minPitch => _minPitch;
  double get maxPitch => _maxPitch;
  bool get isSpeaking => _isSpeaking;
  bool get isInitialized => _initialized;
  SpeechEvent? get lastEvent => _lastEvent;
  int get eventToken => _eventToken;

  Future<void> init() async {
    await _initializePlatformDefaults();
    await _tts.awaitSpeakCompletion(true);
    await _tts.awaitSynthCompletion(true);

    _tts.setStartHandler(() {
      _isSpeaking = true;
      _emitEvent(const SpeechEvent(SpeechEventType.start));
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _emitEvent(const SpeechEvent(SpeechEventType.done));
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _emitEvent(const SpeechEvent(SpeechEventType.stop));
    });
    _tts.setErrorHandler((message) {
      _isSpeaking = false;
      final errorText = message?.toString();
      _emitEvent(SpeechEvent(SpeechEventType.error, errorMessage: errorText));
    });

    await _loadVoices();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadVoices() async {
    dynamic result;
    try {
      result = await _tts.getVoices;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        print("Failed to load voices: $error\n$stackTrace");
      }
      result = null;
    }

    _voices.clear();
    if (result is List) {
      for (final item in result) {
        if (item is Map) {
          final name = item["name"]?.toString();
          final locale = item["locale"]?.toString();
          if (name == null || locale == null) {
            continue;
          }
          _voices.add(
            VoiceOption(
              name: name,
              locale: locale,
              gender: item["gender"]?.toString(),
            ),
          );
        }
      }
    }
    _voices.sort((a, b) => a.displayLabel.compareTo(b.displayLabel));
    _voices.insert(0, defaultVoiceOption);

    final savedVoiceId = _prefs.getString(_voicePreferenceKey);
    VoiceOption? fallback = _voices.length > 1 ? _voices[1] : null;
    if (savedVoiceId == null || savedVoiceId == _systemDefaultVoiceId) {
      _selectedVoice = null;
    } else {
      _selectedVoice = _findVoiceById(savedVoiceId) ?? fallback;
    }
    if (_selectedVoice != null) {
      await _tts.setVoice(_selectedVoice!.toMap());
    }
  }

  VoiceOption? _findVoiceById(String id) {
    for (final voice in _voices) {
      if (voice.id == id) {
        return voice;
      }
    }
    return null;
  }

  Future<void> _initializePlatformDefaults() async {
    _resetRateDefaults();
    _minPitch = Platform.isIOS ? _iosMinPitch : _defaultMinPitch;
    _maxPitch = Platform.isIOS ? _iosMaxPitch : _defaultMaxPitch;

    if (Platform.isIOS || Platform.isMacOS) {
      try {
        final range = await _tts.getSpeechRateValidRange;
        if (range.min > 0 && range.normal > 0 && range.max > 0) {
          if (range.min <= range.normal && range.normal <= range.max) {
            _minRate = range.min;
            _baseRate = range.normal;
            _maxRate = range.max;
          }
        }
      } catch (_) {
      }
    }

    _speed = _baseRate.clamp(_minRate, _maxRate).toDouble();
    _pitch = _pitch.clamp(_minPitch, _maxPitch).toDouble();
  }

  void _resetRateDefaults() {
    _baseRate = _defaultBaseRate;
    _minRate = _defaultBaseRate * _minRateFactor;
    _maxRate = _defaultBaseRate * _maxRateFactor;
  }

  Future<void> _applySpeechSettings() async {
    final clampedRate = _speed.clamp(_minRate, _maxRate).toDouble();
    final clampedPitch = _pitch.clamp(_minPitch, _maxPitch).toDouble();
    await _tts.setSpeechRate(clampedRate);
    await _tts.setPitch(clampedPitch);
    if (_selectedVoice != null) {
      await _tts.setVoice(_selectedVoice!.toMap());
    }
  }

  Future<void> _speakInternal(
    String trimmed, {
    bool reapplySettings = true,
  }) async {
    if (reapplySettings) {
      await _applySpeechSettings();
    }
    _emitEvent(const SpeechEvent(SpeechEventType.beginSynthesis));
    final result = await _tts.speak(trimmed);
    if (result == 1) {
      _emitEvent(const SpeechEvent(SpeechEventType.audioAvailable));
    }
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _speakInternal(trimmed);
  }

  Future<File?> speakWithRecording(String text, String filePath) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    await stop();
    await _applySpeechSettings();
    File? recording;
    final synthTarget = Platform.isIOS ? p.basename(filePath) : filePath;
    final result = await _tts.synthesizeToFile(trimmed, synthTarget);
    if (result == 1) {
      recording = await _resolveRecordingFile(filePath);
    }
    await _speakInternal(trimmed, reapplySettings: false);
    return recording;
  }

  Future<File?> _resolveRecordingFile(String expectedPath) async {
    final expectedFile = File(expectedPath);
    if (await expectedFile.exists()) {
      return expectedFile;
    }
    if (Platform.isIOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      final generatedFile = File(p.join(documentsDir.path, p.basename(expectedPath)));
      if (!await generatedFile.exists()) {
        return null;
      }
      if (p.normalize(generatedFile.path) == p.normalize(expectedPath)) {
        return generatedFile;
      }
      final targetDirectory = expectedFile.parent;
      await targetDirectory.create(recursive: true);
      try {
        final moved = await generatedFile.rename(expectedPath);
        return moved;
      } catch (_) {
        try {
          await generatedFile.copy(expectedPath);
          await generatedFile.delete();
          return expectedFile;
        } catch (_) {
          return null;
        }
      }
    }
    if (!Platform.isAndroid) {
      return null;
    }
    final sanitizedName = expectedPath.replaceAll('/', '_');
    final alternateSanitizedName = sanitizedName.startsWith('_')
        ? sanitizedName.substring(1)
        : null;
    final musicDirs = await getExternalStorageDirectories(
      type: StorageDirectory.music,
    );
    if (musicDirs == null) {
      return null;
    }
    for (final dir in musicDirs) {
      final candidates = <File>{
        File(p.join(dir.path, sanitizedName)),
        if (alternateSanitizedName != null)
          File(p.join(dir.path, alternateSanitizedName)),
      };
      for (final candidate in candidates) {
        if (!await candidate.exists()) {
          continue;
        }
        try {
          final moved = await candidate.rename(expectedPath);
          return moved;
        } catch (_) {
          try {
            await expectedFile.parent.create(recursive: true);
            await candidate.copy(expectedPath);
            await candidate.delete();
            return expectedFile;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  void setSpeed(double value) {
    final clamped = value.clamp(_minRate, _maxRate).toDouble();
    if (_speed == clamped) {
      return;
    }
    _speed = clamped;
    _tts.setSpeechRate(_speed);
    notifyListeners();
  }

  void setPitch(double value) {
    final clamped = value.clamp(_minPitch, _maxPitch).toDouble();
    if (_pitch == clamped) {
      return;
    }
    _pitch = clamped;
    _tts.setPitch(_pitch);
    notifyListeners();
  }

  Future<void> selectVoice(String? voiceId) async {
    if (voiceId == null) {
      return;
    }
    if (voiceId == _systemDefaultVoiceId) {
      if (_selectedVoice == null) {
        return;
      }
      _selectedVoice = null;
      await _prefs.setString(_voicePreferenceKey, _systemDefaultVoiceId);
      notifyListeners();
      return;
    }
    final voice = _findVoiceById(voiceId);
    if (voice == null || _selectedVoice == voice) {
      return;
    }
    _selectedVoice = voice;
    await _tts.setVoice(voice.toMap());
    await _prefs.setString(_voicePreferenceKey, voice.id);
    notifyListeners();
  }

  void _emitEvent(SpeechEvent event) {
    _lastEvent = event;
    _eventToken++;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}
