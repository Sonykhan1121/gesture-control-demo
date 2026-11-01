import 'dart:convert';
import 'package:hand_gesture/features/auth/email_auth_screen.dart';
import '../features/auth/auth_test_support.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/l10n/app_language.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import '../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;

class _Discovery extends DeviceDiscovery {
  @override
  List<DiscoveredDevice> get devices => [];
  @override
  bool get scanning => false;
  @override
  String? get error => null;
  @override
  Future<void> restart() async {}
  @override
  Future<void> stop() async {}
}

Map<String, String> catalog(String language) =>
    (jsonDecode(File('assets/l10n/$language.json').readAsStringSync()) as Map)
        .cast<String, String>();
void main() {
  // Asset futures must not be reused across separate FakeAsync test zones.
  setUp(() => rootBundle.clear());
  test('every catalog has matching keys and preserves all placeholders', () {
    final english = catalog('en');
    for (final code in AppStrings.names.keys) {
      final messages = catalog(code);
      expect(messages.keys.toSet(), english.keys.toSet(), reason: code);
      for (final step in [...gestureTutorialSteps, ...videoTutorialSteps]) {
        expect(
          messages.containsKey(step.title),
          isTrue,
          reason: '$code ${step.title}',
        );
        expect(
          messages.containsKey(step.instruction),
          isTrue,
          reason: '$code ${step.instruction}',
        );
      }
      for (final entry in messages.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: '$code: ${entry.key}');
        Set<String> vars(String s) =>
            RegExp(r'\{\d+\}').allMatches(s).map((m) => m[0]!).toSet();
        expect(
          vars(entry.value),
          vars(entry.key),
          reason: '$code: ${entry.key}',
        );
      }
      final strings = AppStrings(code, messages);
      expect(
        strings.text('MAC Address: A4:C1:38:00:00:01'),
        contains('A4:C1:38:00:00:01'),
      );
      expect(
        strings.text(
          'Enter the 8-digit login code sent to person@example.com.',
        ),
        contains('person@example.com'),
      );
      expect(strings.text('Resend code in 35s'), contains('35'));
      expect(strings.text('Device: Left'), endsWith('Left'));
      expect(strings.text('Device: Language'), endsWith('Language'));
      for (final color in ['Blue', 'Pale green', 'Sky blue', 'White']) {
        expect(
          strings.text('Reaction color $color'),
          messages['Reaction color {0}']!.replaceAll('{0}', messages[color]!),
        );
        expect(strings.text('Device: $color'), endsWith(color));
      }
    }
  });
  test(
    'language selection persists without changing setup or account data',
    () async {
      SharedPreferences.setMockInitialValues({
        'gesture.hand': 'Left',
        'gesture.name': 'Language',
      });
      final prefs = await SharedPreferences.getInstance();
      final language = AppLanguage(prefs);
      await language.select('ja');
      expect(AppLanguage(prefs).code, 'ja');
      expect(prefs.getString('gesture.hand'), 'Left');
      expect(prefs.getString('gesture.name'), 'Language');
      await language.select('invalid');
      expect(language.code, 'ja');
      language.dispose();
    },
  );
  testWidgets(
    'settings language list changes open routes and returns to English',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final c = GestureController(
        await SharedPreferences.getInstance(),
        discovery: _Discovery(),
      );
      c.open(FlowPage.settings);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Language'));
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language-zh')));
      await tester.pumpAndSettle();
      expect(find.text('语言'), findsOneWidget);
      expect(c.preferences.getString('gesture.language'), 'zh');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      await tester.tap(find.text('语言'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-en')));
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  for (final code in AppStrings.names.keys.where((c) => c != 'en')) {
    testWidgets(
      '$code screens fit phone portrait and tablet landscape',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({'gesture.language': code});
        final c = GestureController(
          await SharedPreferences.getInstance(),
          discovery: _Discovery(),
        );
        final old = CameraPlatform.instance;
        CameraPlatform.instance = FakeCameraPlatform();
        addTearDown(() => CameraPlatform.instance = old);
        await tester.pumpWidget(GestureApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.byType(Navigator), findsOneWidget);
        final missing = <String>{};
        final strings = AppStrings(code, catalog(code));
        for (final page in FlowPage.values) {
          c.open(page);
          for (final size in [const Size(393, 852), const Size(1333, 800)]) {
            tester.view.physicalSize = size;
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 50));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 3)),
              );
            }
            expect(tester.takeException(), isNull, reason: '$code $page $size');
            expect(
              find.byType(LText),
              findsWidgets,
              reason: '$code $page must render translated content',
            );
            for (final text in tester.widgetList<LText>(find.byType(LText))) {
              if (strings.text(text.data) == text.data &&
                  RegExp('[A-Za-z]').hasMatch(text.data)) {
                missing.add(text.data);
              }
            }
          }
        }
        if (code == 'zh') {
          expect(
            missing,
            isEmpty,
            reason: 'Visible screen copy must be translated',
          );
        }
        final auth = AuthHarness((_) async => ok({}));
        for (final purpose in EmailAuthPurpose.values) {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => EmailAuthScreen(
                auth: auth.auth,
                purpose: purpose,
                email: 'person@example.com',
                name: 'Test',
                password: 'example-password',
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (purpose != EmailAuthPurpose.registration) {
            final send = find.text(
              strings.text(
                purpose == EmailAuthPurpose.reset
                    ? 'Send reset code'
                    : 'Send code',
              ),
            );
            await tester.ensureVisible(send);
            await tester.tap(send);
            await tester.pumpAndSettle();
          }
          for (final size in [const Size(393, 852), const Size(1333, 800)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$code $purpose $size',
            );
            expect(find.byType(EmailAuthScreen), findsOneWidget);
          }
          navigator.pop();
          await tester.pumpAndSettle();
        }
        auth.auth.dispose();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
