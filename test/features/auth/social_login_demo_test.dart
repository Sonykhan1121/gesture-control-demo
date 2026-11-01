import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/features/auth/social_login_demo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoDiscovery extends DeviceDiscovery {
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

void main() {
  late GestureController controller;
  late SharedPreferences preferences;
  late Map<String, Object?> initialPreferences;
  final boundaryKey = GlobalKey();

  Map<String, Object?> savedPreferences() => {
    for (final key in preferences.getKeys()) key: preferences.get(key),
  };

  Future<void> launch(WidgetTester tester, {bool landscape = false}) async {
    tester.view.physicalSize = landscape
        ? const Size(896, 414)
        : const Size(414, 896);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    controller = GestureController(preferences, discovery: _NoDiscovery());
    controller.open(FlowPage.login);
    // Startup migrations may save tutorial metadata; the auth preview must
    // leave that state unchanged and must not persist a real session.
    initialPreferences = savedPreferences();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: GestureApp(controller: controller, authUiPreview: true),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_AUTH_PREVIEW')) return;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/design/auth-preview/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final provider in ['Google', 'Facebook']) {
    testWidgets(
      '$provider icon starts account choice and existing user reaches Home',
      (tester) async {
        final manrope = FontLoader('Manrope')
          ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await manrope.load();
        await icons.load();
        await launch(tester);
        await screenshot(tester, 'social-login-start');
        await tester.tap(find.byTooltip('Continue with $provider'));
        await tester.pumpAndSettle();
        expect(find.text('$provider sign-in'), findsOneWidget);
        expect(find.text('Choose an account'), findsOneWidget);
        expect(savedPreferences(), initialPreferences);
        await screenshot(tester, '${provider.toLowerCase()}-chooser');
        await tester.tap(find.byKey(const ValueKey('social-existing')));
        await tester.pumpAndSettle();
        expect(controller.page, FlowPage.home);
        expect(controller.name, 'Demo user');
        expect(find.byType(SocialLoginDemo), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('$provider first signup returns to device setup', (
      tester,
    ) async {
      await launch(tester);
      await tester.tap(find.byTooltip('Continue with $provider'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('social-newAccount')));
      await tester.pumpAndSettle();
      expect(controller.page, FlowPage.home);
      expect(controller.name, 'New user');
      expect(controller.device, isNull);
    });

    testWidgets(
      '$provider cancellation and failure stay on Login with bottom message',
      (tester) async {
        await launch(tester);
        await tester.tap(find.byTooltip('Continue with $provider'));
        await tester.pumpAndSettle();
        await tap(tester, 'Cancel');
        expect(controller.page, FlowPage.login);
        expect(find.text('$provider sign-in cancelled.'), findsOneWidget);
        expect(tester.getTopLeft(find.byType(SnackBar)).dy, greaterThan(600));
        expect(savedPreferences(), initialPreferences);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Continue with $provider'));
        await tester.pumpAndSettle();
        await tap(tester, 'Preview other outcomes');
        await tap(tester, 'Sign-in failed');
        expect(
          find.text('$provider sign-in failed. Please try again.'),
          findsOneWidget,
        );
        expect(controller.page, FlowPage.login);
        expect(savedPreferences(), initialPreferences);
      },
    );

    testWidgets(
      '$provider requires explicit link confirmation before sign in',
      (tester) async {
        await launch(tester);
        await tester.tap(find.byTooltip('Continue with $provider'));
        await tester.pumpAndSettle();
        await tap(tester, 'Preview other outcomes');
        await tap(tester, 'Email already has an account');
        await tap(tester, 'Log in to existing account');
        await tester.enterText(
          find.byKey(const ValueKey('Password')),
          'demo12345',
        );
        await tap(tester, 'Continue');
        expect(find.text('Link $provider?'), findsOneWidget);
        expect(controller.page, FlowPage.login);
        expect(savedPreferences(), initialPreferences);
        await screenshot(tester, '${provider.toLowerCase()}-link-confirm');
        await tap(tester, 'Link $provider account');
        expect(find.text('$provider account linked'), findsOneWidget);
        await tap(tester, 'Done');
        expect(controller.page, FlowPage.home);
      },
    );

    testWidgets('$provider conditional email proof completes before Home', (
      tester,
    ) async {
      await launch(tester, landscape: provider == 'Facebook');
      await tester.tap(find.byTooltip('Continue with $provider'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'Preview other outcomes');
      await tap(tester, 'Email verification required');
      await tap(tester, 'Send code');
      await tester.enterText(
        find.byKey(const ValueKey('Verification code')),
        '12345678',
      );
      await tap(tester, 'Verify and continue');
      expect(find.text('Email verified'), findsOneWidget);
      expect(controller.page, FlowPage.login);
      await tap(tester, 'Done');
      expect(controller.page, FlowPage.home);
      expect(tester.takeException(), isNull);
    });
  }
}
