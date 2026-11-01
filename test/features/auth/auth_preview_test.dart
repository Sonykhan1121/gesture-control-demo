import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'package:hand_gesture/features/auth/auth_preview.dart';

void main() {
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signup verification rejects wrong code and returns to review without signing in',
    (tester) async {
      await size(tester, const Size(414, 896));
      await tester.pumpWidget(const AuthPreviewApp());
      await tap(tester, 'Verify signup email');
      await tap(tester, 'Verify email');
      expect(find.text('Enter the 8-digit code.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('Verification code')),
        '11111111',
      );
      await tap(tester, 'Verify email');
      expect(find.text('That code isn’t correct. Try again.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('Verification code')),
        '12345678',
      );
      await tap(tester, 'Verify email');
      expect(find.text('Email verified'), findsOneWidget);
      await tap(tester, 'Back to Log In');
      expect(find.text('Auth UI preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reset requires a code, eight character password and matching confirmation',
    (tester) async {
      await size(tester, const Size(414, 896));
      await tester.pumpWidget(const AuthPreviewApp());
      await tap(tester, 'Forgot password');
      await tap(tester, 'Send reset code');
      await tester.enterText(
        find.byKey(const ValueKey('Verification code')),
        '12345678',
      );
      await tester.enterText(
        find.byKey(const ValueKey('New password')),
        '1234567',
      );
      await tap(tester, 'Reset password');
      expect(
        find.text('Use 8–128 characters for your password.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('New password')),
        'demo12345',
      );
      await tester.enterText(
        find.byKey(const ValueKey('Confirm password')),
        'different',
      );
      await tap(tester, 'Reset password');
      expect(find.text('Your passwords do not match.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('Confirm password')),
        'demo12345',
      );
      await tap(tester, 'Reset password');
      expect(find.text('Password reset'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'linking requires a separate confirmation and supports cancellation',
    (tester) async {
      await size(tester, const Size(414, 896));
      await tester.pumpWidget(const AuthPreviewApp());
      await tap(tester, 'Link an existing account');
      await tap(tester, 'Log in to existing account');
      await tester.enterText(
        find.byKey(const ValueKey('Password')),
        'demo12345',
      );
      await tap(tester, 'Continue');
      expect(find.text('Link Google?'), findsOneWidget);
      await tap(tester, 'Not now');
      expect(find.text('Auth UI preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('email code login waits for resend cooldown and supports back', (
    tester,
  ) async {
    await size(tester, const Size(414, 896));
    await tester.pumpWidget(const AuthPreviewApp());
    await tap(tester, 'Log in with email code');
    await tap(tester, 'Send code');
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Log in with a code'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all preview screens fit portrait and landscape', (tester) async {
    await size(tester, const Size(414, 896));
    final fonts = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    const capture = bool.fromEnvironment('CAPTURE_AUTH_PREVIEW');
    for (final dimensions in [
      const Size(414, 896),
      const Size(896, 414),
      const Size(320, 568),
      const Size(568, 320),
      const Size(800, 1333),
      const Size(1333, 800),
    ]) {
      tester.view.physicalSize = dimensions;
      for (final step in AuthPreviewStep.values) {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: AppTheme.app,
              debugShowCheckedModeBanner: false,
              home: AuthPreviewScreen(key: ValueKey(step), initialStep: step),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${step.name}: $dimensions',
        );
        if (capture && step != AuthPreviewStep.success) {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final orientation = dimensions.width > dimensions.height
              ? 'landscape'
              : 'portrait';
          await tester.runAsync(() async {
            final picture = await boundary.toImage(pixelRatio: 2);
            final data = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'docs/design/auth-preview/${step.name}-$orientation.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
