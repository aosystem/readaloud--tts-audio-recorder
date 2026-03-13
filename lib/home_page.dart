import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "package:readaloud/l10n/app_localizations.dart";
import "package:readaloud/ad_manager.dart";
import "package:readaloud/ad_banner_widget.dart";
import "package:readaloud/parse_locale_tag.dart";
import "package:readaloud/setting_page.dart";
import "package:readaloud/speech_controller.dart";
import "package:readaloud/recording_manager.dart";
import "package:readaloud/recordings_page.dart";
import "package:readaloud/text_tabs_controller.dart";
import "package:readaloud/theme_color.dart";
import "package:readaloud/loading_screen.dart";
import "package:readaloud/model.dart";
import "package:readaloud/theme_mode_number.dart";
import "package:readaloud/main.dart";

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late AdManager _adManager;
  late final TextEditingController _textController;
  late final FocusNode _textFocusNode;
  bool _applyingExternalText = false;
  int? _lastActiveTab;
  int _lastSpeechEventToken = 0;
  String _statusMessage = '';
  //
  late ThemeColor _themeColor;
  bool _isReady = false;
  bool _isFirst = true;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  void _initState() async {
    _adManager = AdManager();
    WidgetsBinding.instance.addObserver(this);
    _textController = TextEditingController();
    _textFocusNode = FocusNode();
    _textController.addListener(_handleTextChanged);
    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  }

  @override
  void dispose() {
    _adManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    if (state == AppLifecycleState.paused) {
      final textTabs = context.read<TextTabsController>();
      textTabs.updateActiveText(_textController.text);
      textTabs.persistAll();
      context.read<SpeechController>().stop();
    }
  }

  void _handleTextChanged() {
    if (_applyingExternalText) {
      return;
    }
    context.read<TextTabsController>().updateActiveText(_textController.text);
  }

  void _applyExternalText(String text) {
    _applyingExternalText = true;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _applyingExternalText = false;
  }

  void _onTabSelected(int index) {
    final textTabs = context.read<TextTabsController>();
    final updatedText = textTabs.switchTo(
      index,
      currentText: _textController.text,
    );
    _applyExternalText(updatedText);
  }

  Future<void> _onPlay() async {
    _textFocusNode.unfocus();
    await context.read<SpeechController>().speak(_textController.text);
  }

  Future<void> _onRecord() async {
    final l = AppLocalizations.of(context);
    final trimmed = _textController.text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _statusMessage = l.recordingEmpty;
      });
      return;
    }
    _textFocusNode.unfocus();
    final recordingManager = context.read<RecordingManager>();
    final speechController = context.read<SpeechController>();
    final messenger = ScaffoldMessenger.of(context);
    final filePath = await recordingManager.createFilePath();
    var hasRecording = false;
    try {
      final file = await speechController.speakWithRecording(
        _textController.text,
        filePath,
      );
      hasRecording = file != null;
    } catch (_) {
      hasRecording = false;
    }
    if (!mounted) {
      return;
    }
    if (hasRecording) {
      await recordingManager.refreshRecordings();
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(l.recordingSaved)));
    } else {
      setState(() {
        _statusMessage = l.recordingFailed;
      });
    }
  }

  Future<void> _onStop() async {
    await context.read<SpeechController>().stop();
  }

  void _onClickSetting() async {
    final updatedSettings = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingPage()),
    );
    if (updatedSettings != null) {
      if (mounted) {
        final mainState = context.findAncestorStateOfType<MainAppState>();
        if (mainState != null) {
          mainState
            ..locale = parseLocaleTag(Model.languageCode)
            ..themeMode = ThemeModeNumber.numberToThemeMode(Model.themeNumber)
            ..setState(() {});
          setState(() {
            _isFirst = true;
          });
        }
      }
    }
  }

  Future<void> _onOpenRecordings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecordingsPage()),
    );
  }

  void _showSpeechEvent(SpeechEvent event, AppLocalizations l) {
    if (!mounted) {
      return;
    }
    String message;
    switch (event.type) {
      case SpeechEventType.beginSynthesis:
        message = l.ttsBeginSynthesis;
        break;
      case SpeechEventType.audioAvailable:
        message = l.ttsAudioAvailable;
        break;
      case SpeechEventType.start:
        message = l.ttsStart;
        break;
      case SpeechEventType.done:
        message = l.ttsDone;
        break;
      case SpeechEventType.stop:
        message = l.ttsStop;
        break;
      case SpeechEventType.error:
        message = l.ttsError;
        if (event.errorMessage != null && event.errorMessage!.isNotEmpty) {
          message = '$message: ${event.errorMessage}';
        }
        break;
    }
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(body: LoadingScreen());
    }
    if (_isFirst) {
      _isFirst = false;
      _themeColor = ThemeColor(
        themeNumber: Model.themeNumber,
        context: context,
      );
    }
    final l = AppLocalizations.of(context);
    final textTabs = context.watch<TextTabsController>();
    final speechController = context.watch<SpeechController>();
    final activeIndex = textTabs.activeIndex;
    if (_lastActiveTab != activeIndex) {
      _applyExternalText(textTabs.activeText);
      _lastActiveTab = activeIndex;
    }
    if (_lastSpeechEventToken != speechController.eventToken &&
        speechController.lastEvent != null) {
      _lastSpeechEventToken = speechController.eventToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSpeechEvent(speechController.lastEvent!, l);
      });
    }
    final tabLabels = ["1", "2", "3", "4", "5", "6", "7", "8", "9"];
    final isSpeaking = speechController.isSpeaking;
    return Scaffold(
      backgroundColor: _themeColor.mainBackColor,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _textFocusNode.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              _TabSelector(
                labels: tabLabels,
                activeIndex: activeIndex,
                onSelected: _onTabSelected,
                onOpenRecordings: _onOpenRecordings,
                onSettings: _onClickSetting,
                recordingsTooltip: l.recordings,
                settingsTooltip: l.setting,
                themeColor: _themeColor,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 8,
                    bottom: 100,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCardTextField(),
                      _buildCardVoice(speechController),
                      _buildCardVocalization(isSpeaking),
                      _buildCardStatus(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AdBannerWidget(adManager: _adManager),
    );
  }

  Widget _buildVoice(SpeechController speechController) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final voiceOptions = speechController.voices;
    final selectedVoiceId = speechController.selectedVoice?.id;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l.voice,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _themeColor.mainForeColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InputDecorator(
            decoration: InputDecoration(
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: voiceOptions.isEmpty ? null : selectedVoiceId,
                hint: Text(l.voice),
                items: voiceOptions
                    .map(
                      (voice) => DropdownMenuItem<String>(
                        value: voice.id,
                        child: Text(
                          voice.displayLabel,
                          style: TextStyle(color: _themeColor.mainForeColor),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: voiceOptions.isEmpty
                    ? null
                    : (value) =>
                          context.read<SpeechController>().selectVoice(value),
                dropdownColor: _themeColor.mainDropdownColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardTextField() {
    return Card(
      color: _themeColor.mainCardColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              minLines: 4,
              maxLines: null,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: _themeColor.mainForeColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVoice(SpeechController speechController) {
    final l = AppLocalizations.of(context);
    final baseRate = speechController.baseRate;
    final minRate = speechController.minRate;
    final maxRate = speechController.maxRate;
    final minPitch = speechController.minPitch;
    final maxPitch = speechController.maxPitch;
    final normalizedBaseRate = baseRate <= 0 ? 1.0 : baseRate;
    return Card(
      color: _themeColor.mainCardColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVoice(speechController),
            const SizedBox(height: 16),
            _SliderRow(
              label: l.speed,
              valueLabel:
                  '${(speechController.speed / normalizedBaseRate * 100).round()}%',
              value: speechController.speed / normalizedBaseRate,
              min: minRate / normalizedBaseRate,
              max: maxRate / normalizedBaseRate,
              onChanged: (normalized) => context
                  .read<SpeechController>()
                  .setSpeed(normalized * normalizedBaseRate),
              themeColor: _themeColor,
            ),
            const SizedBox(height: 12),
            _SliderRow(
              label: l.pitch,
              valueLabel: '${(speechController.pitch * 100).round()}%',
              value: speechController.pitch,
              min: minPitch,
              max: maxPitch,
              onChanged: context.read<SpeechController>().setPitch,
              themeColor: _themeColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVocalization(bool isSpeaking) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: _themeColor.mainCardColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FilledButton(
                onPressed: isSpeaking ? null : _onPlay,
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                child: Text(l.play),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isSpeaking ? _onStop : null,
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                child: Text(l.stop),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isSpeaking ? null : _onRecord,
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                      ? colorScheme.errorContainer
                      : colorScheme.error,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                      ? colorScheme.onErrorContainer
                      : colorScheme.onError,
                  ),
                ),
                child: Text(l.record),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStatus() {
    final textStyle = Theme.of(context,
    ).textTheme.bodySmall?.copyWith(color: _themeColor.mainForeColor);
    return Card(
      color: _themeColor.mainCardColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: Text(_statusMessage, style: textStyle))],
        ),
      ),
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({
    required this.labels,
    required this.activeIndex,
    required this.onSelected,
    required this.onOpenRecordings,
    required this.onSettings,
    required this.recordingsTooltip,
    required this.settingsTooltip,
    required this.themeColor,
  });
  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenRecordings;
  final VoidCallback onSettings;
  final String recordingsTooltip;
  final String settingsTooltip;
  final ThemeColor themeColor;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      elevation: 0,
    );

    Widget buildTabButton(int index) {
      final selected = index == activeIndex;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: ElevatedButton(
            onPressed: () => onSelected(index),
            style: baseStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                selected ? colorScheme.primary : themeColor.mainCardColor,
              ),
              foregroundColor: WidgetStatePropertyAll(
                selected ? Colors.white : Colors.grey[500],
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
            child: Text(labels[index]),
          ),
        ),
      );
    }

    Widget buildRecordingsButton() {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Tooltip(
            message: recordingsTooltip,
            child: ElevatedButton(
              onPressed: onOpenRecordings,
              style: baseStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(themeColor.mainCardColor),
                foregroundColor: WidgetStatePropertyAll(Colors.grey[500]),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              child: const Icon(Icons.list),
            ),
          ),
        ),
      );
    }

    Widget buildSettingsButton() {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Tooltip(
            message: settingsTooltip,
            child: ElevatedButton(
              onPressed: onSettings,
              style: baseStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(themeColor.mainCardColor),
                foregroundColor: WidgetStatePropertyAll(Colors.grey[500]),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
              child: const Icon(Icons.settings),
            ),
          ),
        ),
      );
    }

    Widget buildDummyButton() {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: ElevatedButton(
            onPressed: null,
            style: baseStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(themeColor.mainCardColor),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
            child: const SizedBox(height:18),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.transparent),
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [for (var i = 0; i < 6; i++) buildTabButton(i)]),
          Row(
            children: [
              for (var i = 6; i < 9; i++) buildTabButton(i),
              buildDummyButton(),
              buildRecordingsButton(),
              buildSettingsButton(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.themeColor,
  });
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ThemeColor themeColor;
  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: themeColor.mainForeColor,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: themeColor.mainForeColor),
            ),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: ((max - min) / 0.1).round(),
          label: "${(clampedValue * 100).toInt()}%",
          value: clampedValue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
