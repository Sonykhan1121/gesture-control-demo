import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/features/auth/services/auth_api.dart';
import 'package:hand_gesture/features/auth/services/auth_service.dart';
import 'package:hand_gesture/features/auth/services/demo_auth.dart';
import 'auth_test_support.dart' show MemoryAuthStore;

void main() {
  late DemoAuthApi api;
  late AuthService auth;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = DemoAuthApi(prefs);
    await api.initialize();
    auth = AuthService(
      api: api,
      store: MemoryAuthStore(),
      browser: DemoSocialBrowser(),
    );
  });
  tearDown(() => auth.dispose());
  test('sample login, refresh, restore and logout remain local', () async {
    final session = await auth.login(DemoAuthApi.email, DemoAuthApi.password);
    expect(session.name, 'Demo Explorer');
    expect(await auth.restore(), isTrue);
    final renewed = await api.request(
      'POST',
      '/auth/refresh',
      body: {'refreshToken': session.refreshToken},
    );
    expect(renewed['session']['id'], session.sessionId);
    final newApi = DemoAuthApi(prefs);
    await newApi.initialize();
    expect(
      (await newApi.request(
        'GET',
        '/auth/me',
        accessToken: session.accessToken,
      ))['user']['email'],
      DemoAuthApi.email,
    );
    await auth.logout();
    await expectLater(
      api.request('GET', '/auth/me', accessToken: session.accessToken),
      throwsA(isA<AuthFailure>()),
    );
  });
  test('local registration, OTP rejection, code login and reset', () async {
    const email = 'visitor@example.com';
    await auth.requestRegistration('Visitor', email, 'Sample123!');
    await expectLater(
      auth.verifyRegistration(email, '00000000'),
      throwsA(isA<AuthFailure>()),
    );
    await auth.verifyRegistration(email, DemoAuthApi.otp);
    final old = await auth.login(email, 'Sample123!');
    await auth.requestLoginCode(email);
    expect((await auth.verifyLoginCode(email, DemoAuthApi.otp)).userId, email);
    await auth.requestPasswordReset(email);
    await auth.resetPassword(email, DemoAuthApi.otp, 'Changed123!');
    await expectLater(
      auth.login(email, 'Sample123!'),
      throwsA(isA<AuthFailure>()),
    );
    expect((await auth.login(email, 'Changed123!')).name, 'Visitor');
    await expectLater(
      api.request('GET', '/auth/me', accessToken: old.accessToken),
      throwsA(isA<AuthFailure>()),
    );
  });
  for (final provider in ['google', 'facebook']) {
    test(
      '$provider simulates the callback and code exchange in process',
      () async {
        final pending = await auth.authorize(provider);
        final session = await auth.exchange(pending);
        expect(session.user['email'], 'demo.$provider@example.com');
        expect(await auth.restore(), isTrue);
      },
    );
  }
  test('default auth transport cannot contact a backend', () async {
    final fallback = AuthApi();
    await expectLater(
      fallback.request('POST', '/auth/login'),
      throwsA(isA<AuthFailure>()),
    );
    fallback.close();
  });
}
