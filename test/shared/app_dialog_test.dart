import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/app_dialog.dart';

void main() {
  testWidgets(
    'translated centered dialogs keep actions reachable with large text and keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [
        const Size(320, 568),
        const Size(568, 320),
        const Size(800, 1333),
      ]) {
        tester.view.physicalSize = size;
        for (final locale in AppStrings.locales) {
          var acted = false;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppStrings.locales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: const TextScaler.linear(1.5),
                  viewInsets: const EdgeInsets.only(bottom: 100),
                ),
                child: AppDialog(
                  title: 'Allow Bluetooth access',
                  icon: Icons.bluetooth,
                  message:
                      'Allow lazivoo to use Bluetooth to find nearby devices.',
                  actions: [
                    appDialogAction('Not now', () {}, primary: false),
                    appDialogAction(
                      'Open app settings',
                      () => acted = true,
                      key: const ValueKey('primary'),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final primary = find.byKey(const ValueKey('primary'));
          await tester.ensureVisible(primary);
          await tester.pumpAndSettle();
          await tester.tap(primary);
          expect(acted, isTrue, reason: '$locale $size');
          expect(tester.takeException(), isNull, reason: '$locale $size');
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
    },
  );
}
