import 'package:hand_gesture/shared/settings_asset_warmup.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/l10n/app_language.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/flow/gesture_screen.dart';
import 'dart:async';

class GestureApp extends StatefulWidget {
  const GestureApp({
    super.key,
    required this.controller,
    this.authUiPreview = false,
  });
  final GestureController controller;
  final bool authUiPreview;
  @override
  State<GestureApp> createState() => _GestureAppState();
}

class _GestureAppState extends State<GestureApp> with WidgetsBindingObserver {
  late final AppLanguage language = AppLanguage(widget.controller.preferences);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    language.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.auth?.foregroundActivity(opened: true));
    }
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.controller,
    child: ChangeNotifierProvider.value(
      value: language,
      child: ListenableBuilder(
        listenable: language,
        builder: (context, _) => MaterialApp(
          locale: language.locale,
          supportedLocales: AppStrings.locales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          title: 'Gesture Control Demo',
          builder: (_, child) => Banner(
            message: 'DEMO',
            location: BannerLocation.topEnd,
            child: child!,
          ),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.app,
          home: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) {
                unawaited(widget.controller.auth?.foregroundActivity());
              }
            },
            child: SettingsAssetWarmup(
              child: GestureScreen(authUiPreview: widget.authUiPreview),
            ),
          ),
        ),
      ),
    ),
  );
}
