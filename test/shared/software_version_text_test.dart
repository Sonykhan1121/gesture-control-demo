import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/shared/software_version_text.dart';
import 'package:hand_gesture/l10n/app_strings.dart';

void main() {
  testWidgets(
    'Version text follows installed metadata and translated templates',
    (t) async {
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SoftwareVersionText.channel,
          null,
        ),
      );
      for (final locale in [
        'en',
        'zh',
        'ja',
        'th',
        'vi',
        'id',
        'ms',
        'fil',
        'pt',
      ]) {
        for (final version in ['0.1.0', '2.4.7']) {
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SoftwareVersionText.channel,
            (call) async => {'version': version, 'buildNumber': '42'},
          );
          await t.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              locale: Locale(locale),
              supportedLocales: AppStrings.locales,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(
                body: SoftwareVersionText(style: TextStyle()),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.textContaining('$version+42'), findsOneWidget);
          expect(find.textContaining('1.0.1'), findsNothing);
          if (locale != 'en') {
            expect(find.textContaining('Software Version:'), findsNothing);
          }
          expect(t.takeException(), isNull);
        }
      }
    },
  );
}
