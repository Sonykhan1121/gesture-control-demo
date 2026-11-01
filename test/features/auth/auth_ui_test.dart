import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/auth/email_auth_screen.dart';
import 'package:hand_gesture/features/auth/social_sign_in_screen.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_test_support.dart';

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
  Future<void> launch(
    WidgetTester tester,
    AuthHarness h, {
    FlowPage page = FlowPage.login,
    bool landscape = false,
  }) async {
    tester.view.physicalSize = landscape
        ? const Size(896, 414)
        : const Size(414, 896);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'gesture.cameraX': .27,
      'gesture.hand': 'Left',
    });
    preferences = await SharedPreferences.getInstance();
    controller = GestureController(
      preferences,
      discovery: _NoDiscovery(),
      auth: h.auth,
    );
    controller.open(page);
    await tester.pumpWidget(GestureApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String label, String text) =>
      tester.enterText(find.byKey(ValueKey(label)), text);

  for (final landscape in [false, true]) {
    testWidgets(
      'Google icon opens chooser and accepts chosen profile (landscape: $landscape)',
      (tester) async {
        final h = AuthHarness(
          (r) async => r.url.path.endsWith('/native/start')
              ? ok(startData())
              : ok(bundle(userId: 'other-google-user')),
        );
        await launch(tester, h, landscape: landscape);
        expect(find.text('Use another Google account'), findsNothing);
        await tester.tap(find.byTooltip('Continue with Google'));
        await tester.pumpAndSettle();
        expect(h.browser.opened!.queryParameters['prompt'], 'select_account');
        expect(controller.page, FlowPage.home);
        expect(h.auth.session!.userId, 'other-google-user');
        expect(
          h.requests.any((r) => r.url.path.endsWith('/native/link')),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('login tolerates a zero-sized Android surface then recovers', (
    tester,
  ) async {
    final h = AuthHarness((r) async => ok({'message': 'Done'}));
    await launch(tester, h);
    tester.view.physicalSize = Size.zero;
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real password login failure stays on login and shows bottom notice',
    (tester) async {
      final h = AuthHarness(
        (r) async => rejected('INVALID_CREDENTIALS', status: 401),
      );
      await launch(tester, h);
      await type(tester, 'Email', 'test@example.com');
      await type(tester, 'Password', 'wrong123');
      await tap(tester, 'Log In');
      expect(controller.page, FlowPage.login);
      expect(h.store.value, isNull);
      expect(find.text('The email or password is incorrect.'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(SnackBar)).dy, greaterThan(600));
      expect(preferences.getBool('gesture.demoSession'), isNull);
    },
  );

  testWidgets('real password login and logout preserve device setup', (
    tester,
  ) async {
    final h = AuthHarness(
      (r) async => r.url.path.endsWith('/logout')
          ? ok({'message': 'Done'})
          : ok(bundle()),
    );
    await launch(tester, h);
    await type(tester, 'Email', 'test@example.com');
    await type(tester, 'Password', 'password123');
    await tap(tester, 'Log In');
    expect(controller.page, FlowPage.home);
    expect(controller.name, 'Test User');
    expect(preferences.getBool('gesture.demoSession'), isFalse);
    expect(preferences.getBool('gesture.realSession'), isTrue);
    await controller.logout();
    await tester.pumpAndSettle();
    expect(controller.page, FlowPage.login);
    expect(h.store.value, isNull);
    expect(preferences.getDouble('gesture.cameraX'), .27);
    expect(preferences.getString('gesture.hand'), 'Left');
  });

  testWidgets(
    'signup verifies OTP and automatically signs in with the registration password',
    (tester) async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/auth/login')
            ? ok(bundle())
            : ok({'message': 'Done'}, status: 200),
      );
      await launch(tester, h, page: FlowPage.createAccount);
      await type(tester, 'Full Name', 'Tester');
      await type(tester, 'Email', 'test@example.com');
      await type(tester, 'Password', '1234567');
      await type(tester, 'Confirm Password', '1234567');
      await tap(tester, 'Next');
      expect(h.requests, isEmpty);
      expect(
        find.text('Use at least 8 characters for your password.'),
        findsOneWidget,
      );
      await type(tester, 'Password', 'password123');
      await type(tester, 'Confirm Password', 'password123');
      await tap(tester, 'Next');
      expect(find.byType(EmailAuthScreen), findsOneWidget);
      await type(tester, 'Verification code', '01234567');
      await tap(tester, 'Verify email');
      expect(controller.page, FlowPage.home);
      expect(h.store.writes, 1);
      expect(body(h.requests.last)['password'], 'password123');
      expect(body(h.requests.last)['email'], 'test@example.com');
      expect(h.auth.session, isNotNull);
    },
  );

  for (final landscape in [false, true]) {
    testWidgets(
      'registration retries login without consuming OTP twice ($landscape)',
      (tester) async {
        var loginAttempts = 0;
        final h = AuthHarness((r) async {
          if (r.url.path.endsWith('/auth/login')) {
            return ++loginAttempts == 1 ? rejected('NETWORK') : ok(bundle());
          }
          return ok({'message': 'Done'});
        });
        await launch(
          tester,
          h,
          page: FlowPage.createAccount,
          landscape: landscape,
        );
        await type(tester, 'Full Name', 'Tester');
        await type(tester, 'Email', 'test@example.com');
        await type(tester, 'Password', 'password123');
        await type(tester, 'Confirm Password', 'password123');
        await tap(tester, 'Next');
        await type(tester, 'Verification code', '01234567');
        await tap(tester, 'Verify email');
        expect(find.text('Account created'), findsOneWidget);
        expect(h.auth.session, isNull);
        expect(find.byKey(const ValueKey('Verification code')), findsNothing);
        await tap(tester, 'Continue');
        expect(controller.page, FlowPage.home);
        expect(
          h.requests
              .where((r) => r.url.path.endsWith('/register/verify'))
              .length,
          1,
        );
        expect(loginAttempts, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'existing email OTP login is reached from login and validates server code',
    (tester) async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/verify')
            ? ok(bundle())
            : ok({'message': 'Done'}, status: 202),
      );
      await launch(tester, h);
      await tap(tester, 'Log in with a code');
      await type(tester, 'Email', 'test@example.com');
      await tap(tester, 'Send code');
      expect(find.textContaining('Resend code in'), findsOneWidget);
      await type(tester, 'Verification code', '01234567');
      await tap(tester, 'Log In');
      expect(controller.page, FlowPage.home);
      expect(h.requests.last.url.path.endsWith('/login/otp/verify'), isTrue);
    },
  );

  testWidgets(
    'forgot password sends code with new password, does not auto-login',
    (tester) async {
      final h = AuthHarness((r) async => ok({'message': 'Done'}, status: 202));
      await launch(tester, h, landscape: true);
      await tap(tester, 'Forgot Password?');
      await type(tester, 'Email', 'test@example.com');
      await tap(tester, 'Send reset code');
      await type(tester, 'Verification code', '01234567');
      await type(tester, 'New password', 'password123');
      await type(tester, 'Confirm password', 'different123');
      await tap(tester, 'Reset password');
      expect(find.text('Your passwords do not match.'), findsOneWidget);
      expect(h.requests.length, 1);
      await type(tester, 'Confirm password', 'password123');
      await tap(tester, 'Reset password');
      expect(find.text('Password reset'), findsOneWidget);
      expect(body(h.requests.last)['newPassword'], 'password123');
      await tap(tester, 'Back to Log In');
      expect(controller.page, FlowPage.login);
      expect(h.auth.session, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real provider cancellation returns to login without demo profile',
    (tester) async {
      final h = AuthHarness((r) async => ok(startData()));
      h.browser.respond = (_) async =>
          h.browser.callback(status: 'error', error: 'CANCELLED');
      await launch(tester, h);
      await tester.tap(find.byTooltip('Continue with Google'));
      await tester.pumpAndSettle();
      expect(controller.page, FlowPage.login);
      expect(find.byType(SocialSignInScreen), findsNothing);
      expect(preferences.getBool('gesture.demoSession'), isNull);
      expect(h.store.writes, 0);
    },
  );

  for (final provider in ['Google', 'Facebook']) {
    testWidgets(
      '$provider link conflict requires password and explicit consent before native link',
      (tester) async {
        final h = AuthHarness((r) async {
          if (r.url.path.endsWith('/native/start') ||
              r.url.path.endsWith('/native/link')) {
            return ok(startData(provider.toLowerCase()));
          }
          if (r.url.path.endsWith('/logout')) return ok({'message': 'Done'});
          return ok(bundle());
        });
        h.browser.respond = (_) async => h.browser.opens == 1
            ? h.browser.callback(
                status: 'error',
                error: 'ACCOUNT_LINK_REQUIRED',
              )
            : h.browser.callback();
        await launch(tester, h);
        await tester.tap(find.byTooltip('Continue with $provider'));
        await tester.pumpAndSettle();
        await tap(tester, 'Log in to existing account');
        await type(tester, 'Email', 'test@example.com');
        await type(tester, 'Password', 'password123');
        await tap(tester, 'Continue');
        expect(find.text('Link $provider?'), findsOneWidget);
        expect(
          h.requests.where((r) => r.url.path.endsWith('/native/link')),
          isEmpty,
        );
        expect(h.store.writes, 0);
        await tap(tester, 'Link $provider account');
        expect(controller.page, FlowPage.home);
        expect(h.auth.session, isNotNull);
      },
    );
  }

  testWidgets(
    'guest selection forgets stored real session and stays guest after restart',
    (tester) async {
      final h = AuthHarness((r) async => ok({'message': 'Done'}));
      h.store.value = 'old secure session';
      await launch(tester, h);
      await tap(tester, 'Skip -use as guest');
      expect(controller.name, 'Guest');
      expect(h.store.value, isNull);
      expect(preferences.getBool('gesture.guestSession'), isTrue);
      expect(preferences.getDouble('gesture.cameraX'), .27);
    },
  );
}
