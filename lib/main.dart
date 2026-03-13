import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import "package:readaloud/home_page.dart";
import 'package:readaloud/l10n/app_localizations.dart';
import 'package:readaloud/loading_screen.dart';
import 'package:readaloud/model.dart';
import 'package:readaloud/parse_locale_tag.dart';
import 'package:readaloud/speech_controller.dart';
import 'package:readaloud/recording_manager.dart';
import 'package:readaloud/text_tabs_controller.dart';
import 'package:readaloud/theme_mode_number.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  MobileAds.instance.initialize();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  ThemeMode themeMode = ThemeMode.light;
  Locale? locale;
  bool _isReady = false;
  TextTabsController? _textTabsController;
  SpeechController? _speechController;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  void _initState() async {
    await Model.ensureReady();
    final prefs = await SharedPreferences.getInstance();
    _textTabsController = TextTabsController(prefs);
    _speechController = SpeechController(prefs);
    await Future.wait([_textTabsController!.load(), _speechController!.init()]);
    themeMode = ThemeModeNumber.numberToThemeMode(Model.themeNumber);
    locale = parseLocaleTag(Model.languageCode);
    if (!mounted) {
      return;
    }
    setState(() {
      _isReady = true;
    });
  }

  @override
  void dispose() {
    _textTabsController?.dispose();
    _speechController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: LoadingScreen())),
      );
    }
    const seed = Colors.blueAccent;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RecordingManager>(
          create: (_) => RecordingManager(),
        ),
        ChangeNotifierProvider<TextTabsController>.value(
          value: _textTabsController!,
        ),
        ChangeNotifierProvider<SpeechController>.value(
          value: _speechController!,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        themeMode: themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
