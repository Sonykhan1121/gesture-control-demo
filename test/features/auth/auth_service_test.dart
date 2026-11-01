import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/auth/services/auth_api.dart';
import 'package:hand_gesture/features/auth/services/auth_service.dart';
import 'package:hand_gesture/features/auth/services/auth_session.dart';
import 'package:http/http.dart' as http;
import 'auth_test_support.dart';

void main() {
  test(
    'Google chooser preserves OAuth proofs and does not link accounts',
    () async {
      final original = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'state': testState,
        'code_challenge': 'challenge',
        'code_challenge_method': 'S256',
        'nonce': 'nonce',
        'scope': 'openid email profile',
        'client_id': 'client',
        'redirect_uri': 'https://example.com/callback',
        'prompt': 'consent',
        'login_hint': 'old@example.com',
        'authuser': '0',
      });
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/native/start')
            ? ok({'state': testState, 'authorizationUrl': original.toString()})
            : ok(bundle(userId: 'chosen-user')),
      );
      final pending = await h.auth.authorize(
        'google',
        chooseGoogleAccount: true,
      );
      final query = h.browser.opened!.queryParameters;
      for (final key in [
        'state',
        'code_challenge',
        'code_challenge_method',
        'nonce',
        'scope',
        'client_id',
        'redirect_uri',
      ]) {
        expect(query[key], original.queryParameters[key]);
      }
      expect(query['prompt'], 'consent select_account');
      expect(query.containsKey('login_hint'), isFalse);
      expect(query.containsKey('authuser'), isFalse);
      await h.auth.exchange(pending);
      expect(h.auth.session!.userId, 'chosen-user');
      expect(
        h.requests.any((r) => r.url.path.endsWith('/native/link')),
        isFalse,
      );
      expect(h.requests.last.headers['Authorization'], isNull);
      h.auth.dispose();
    },
  );

  test(
    'quick Google login keeps the backend authorization URL unchanged',
    () async {
      final h = AuthHarness((r) async => ok(startData()));
      await h.auth.authorize('google');
      expect(h.browser.opened.toString(), startData()['authorizationUrl']);
      h.auth.dispose();
    },
  );

  for (final display in [null, 'page', 'touch']) {
    test(
      'Facebook Android mobile host preserves OAuth parameters and verifier ($display)',
      () async {
        final original = Uri.https('www.facebook.com', '/v26.0/dialog/oauth', {
          'state': testState,
          'redirect_uri': 'https://example.com/facebook/callback',
          'response_type': 'code',
          'scope': 'email,public_profile',
          'client_id': 'client',
          'nonce': 'nonce',
          'code_challenge': 'challenge',
          'code_challenge_method': 'S256',
          'extra': ['first', 'second'],
          if (display != null) 'display': display,
        });
        final h = AuthHarness(
          (r) async => r.url.path.endsWith('/native/start')
              ? ok({
                  'state': testState,
                  'authorizationUrl': original.toString(),
                })
              : ok(bundle()),
        );
        addTearDown(h.auth.dispose);
        final pending = await h.auth.authorize('facebook');
        final expected = Map<String, List<String>>.from(
          original.queryParametersAll,
        )..['display'] = ['touch'];
        expect(h.browser.opened!.queryParametersAll, expected);
        expect(h.browser.opened!.host, 'm.facebook.com');
        expect(h.browser.opened!.path, original.path);
        expect(pending.state, testState);
        expect(
          body(h.requests.first)['codeChallenge'],
          AuthService.challengeFor(testVerifier),
        );
        await h.auth.exchange(pending);
        expect(body(h.requests.last)['codeVerifier'], testVerifier);
        expect(body(h.requests.last)['code'], 'completion-one');
        expect(h.auth.session!.userId, 'user-one');
      },
    );
  }

  test('Facebook iOS keeps the backend dialog host', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final original = Uri.https('www.facebook.com', '/v26.0/dialog/oauth', {
      'state': testState,
      'redirect_uri': 'https://example.com/facebook/callback',
    });
    final h = AuthHarness(
      (r) async =>
          ok({'state': testState, 'authorizationUrl': original.toString()}),
    );
    addTearDown(h.auth.dispose);
    await h.auth.authorize('facebook');
    expect(h.browser.opened!.host, original.host);
    expect(h.browser.opened!.path, original.path);
    expect(h.browser.opened!.queryParameters['state'], testState);
    expect(h.browser.opened!.queryParameters['display'], 'touch');
  });

  test('PKCE S256 matches the RFC 7636 example', () {
    expect(
      AuthService.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test(
    'password login uses native headers, normalized email, exact password and secure session',
    () async {
      final h = AuthHarness((r) async => ok(bundle()));
      final result = await h.auth.login(
        ' Test@Example.com ',
        ' Password stays exact ',
      );
      final r = h.requests.single;
      expect(r.url.path, '/auth/login');
      expect(r.headers['X-Client-Type'], 'native');
      expect(
        r.headers.keys.map((s) => s.toLowerCase()),
        isNot(contains('origin')),
      );
      expect(
        r.headers.keys.map((s) => s.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(body(r)['email'], 'test@example.com');
      expect(body(r)['password'], ' Password stays exact ');
      expect(result.name, 'Test User');
      expect(AuthSession.decode(h.store.value!).refreshToken, 'refresh-one');
      h.auth.dispose();
    },
  );

  test('signup request and verify never create a local session', () async {
    final h = AuthHarness(
      (r) async => ok({
        'message': 'Accepted',
      }, status: r.url.path.endsWith('request-otp') ? 202 : 200),
    );
    await h.auth.requestRegistration(
      ' Test User ',
      ' TEST@example.com ',
      'password123',
    );
    await h.auth.verifyRegistration(' TEST@example.com ', '01234567');
    expect(body(h.requests.first), {
      'name': 'Test User',
      'email': 'test@example.com',
      'password': 'password123',
    });
    expect(body(h.requests.last), {
      'email': 'test@example.com',
      'otp': '01234567',
    });
    expect(h.auth.session, isNull);
    expect(h.store.writes, 0);
    h.auth.dispose();
  });

  test(
    'login OTP and reset OTP use separate purpose-specific endpoints',
    () async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/login/otp/verify')
            ? ok(bundle())
            : ok({'message': 'Accepted'}, status: 202),
      );
      await h.auth.requestLoginCode('test@example.com');
      await h.auth.verifyLoginCode('test@example.com', '01234567');
      await h.auth.requestPasswordReset('test@example.com');
      await h.auth.resetPassword(
        'test@example.com',
        '87654321',
        'newpassword123',
      );
      expect(h.requests.map((r) => r.url.path.split('/v1').last), [
        '/auth/login/otp/request',
        '/auth/login/otp/verify',
        '/auth/password/reset/request',
        '/auth/password/reset/confirm',
      ]);
      expect(body(h.requests.last), {
        'email': 'test@example.com',
        'otp': '87654321',
        'newPassword': 'newpassword123',
      });
      expect(h.auth.session, isNull);
      expect(h.store.value, isNull);
      h.auth.dispose();
    },
  );

  for (final provider in ['google', 'facebook']) {
    test(
      '$provider native flow binds state and verifier before storing real user',
      () async {
        final h = AuthHarness(
          (r) async => r.url.path.endsWith('/native/start')
              ? ok(startData(provider))
              : ok(bundle()),
        );
        final pending = await h.auth.authorize(provider);
        expect(body(h.requests.first), {
          'codeChallenge': AuthService.challengeFor(testVerifier),
        });
        expect(h.store.value, isNull);
        await h.auth.exchange(pending);
        expect(body(h.requests.last)['codeVerifier'], testVerifier);
        expect(body(h.requests.last)['code'], 'completion-one');
        expect(h.requests.last.headers['Authorization'], isNull);
        expect(h.auth.session!.userId, 'user-one');
        await expectLater(
          h.auth.exchange(pending),
          throwsA(isA<AuthFailure>()),
        );
        expect(h.requests.length, 2);
        h.auth.dispose();
      },
    );
  }

  for (final invalid in ['state', 'host', 'path', 'duplicate', 'unsolicited']) {
    test('rejects $invalid callback without exchanging credentials', () async {
      final h = AuthHarness((r) async => ok(startData()));
      h.browser.respond = (_) async => switch (invalid) {
        'state' => h.browser.callback(state: 'different'),
        'host' => h.browser.callback().replace(host: 'evil'),
        'path' => h.browser.callback().replace(path: '/other'),
        'duplicate' => Uri.parse('${h.browser.callback()}&state=$testState'),
        _ => Uri.parse('$gisterNativeCallback?social_status=ready&code=stolen'),
      };
      await expectLater(
        h.auth.authorize('google'),
        throwsA(isA<AuthFailure>()),
      );
      expect(h.requests.length, 1);
      expect(h.store.value, isNull);
      h.auth.dispose();
    });
  }

  test('rejects non-provider authorization hosts', () async {
    final h = AuthHarness(
      (r) async => ok({
        ...startData(),
        'authorizationUrl': 'https://accounts.google.com.evil.test/auth',
      }),
    );
    await expectLater(h.auth.authorize('google'), throwsA(isA<AuthFailure>()));
    expect(h.browser.opens, 0);
    h.auth.dispose();
  });

  test('cancelled authorization never exchanges or stores tokens', () async {
    final h = AuthHarness((r) async => ok(startData()));
    final callback = Completer<Uri>();
    h.browser.respond = (_) => callback.future;
    final operation = h.auth.authorize('google');
    await Future<void>.delayed(Duration.zero);
    h.auth.cancelAttempt();
    callback.complete(h.browser.callback());
    await expectLater(operation, throwsA(isA<AuthFailure>()));
    expect(h.requests.length, 1);
    expect(h.store.value, isNull);
    h.auth.dispose();
  });

  test(
    'social email verification exchanges the new code and preserves original proof',
    () async {
      final h = AuthHarness((r) async {
        if (r.url.path.endsWith('/native/start')) return ok(startData());
        if (r.url.path.endsWith('/email/verify')) {
          return ok({'code': 'replacement-code'});
        }
        if (r.url.path.endsWith('/exchange')) return ok(bundle());
        return ok({'message': 'Accepted'}, status: 202);
      });
      h.browser.respond = (_) async =>
          h.browser.callback(status: 'email_verification_required');
      final pending = await h.auth.authorize('google');
      await expectLater(h.auth.exchange(pending), throwsA(isA<AuthFailure>()));
      await h.auth.requestSocialEmail(pending, ' TEST@example.com ');
      await h.auth.verifySocialEmail(pending, '01234567');
      await h.auth.exchange(pending);
      expect(body(h.requests.last)['code'], 'replacement-code');
      for (final r in h.requests.skip(1)) {
        expect(body(r)['codeVerifier'], testVerifier);
      }
      h.auth.dispose();
    },
  );

  test(
    'link login stays temporary and linking uses same user Bearer session',
    () async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/native/link')
            ? ok(startData('facebook'))
            : ok(bundle()),
      );
      final temporary = await h.auth.loginForLink(
        'test@example.com',
        'password123',
      );
      expect(h.auth.session, isNull);
      expect(h.store.writes, 0);
      final pending = await h.auth.authorize(
        'facebook',
        linkSession: temporary,
      );
      await h.auth.exchange(pending);
      expect(h.requests[1].headers['Authorization'], 'Bearer access-one');
      expect(h.requests[2].headers['Authorization'], 'Bearer access-one');
      expect(h.auth.session!.userId, temporary.userId);
      h.auth.dispose();
    },
  );

  test('link exchange cannot switch to a different user', () async {
    var calls = 0;
    final h = AuthHarness((r) async {
      calls++;
      return r.url.path.endsWith('/native/link')
          ? ok(startData())
          : ok(bundle(userId: calls > 2 ? 'wrong-user' : 'user-one'));
    });
    final temporary = await h.auth.loginForLink(
      'test@example.com',
      'password123',
    );
    final pending = await h.auth.authorize('google', linkSession: temporary);
    await expectLater(h.auth.exchange(pending), throwsA(isA<AuthFailure>()));
    expect(h.store.writes, 0);
    h.auth.dispose();
  });

  test('concurrent protected requests serialize refresh rotation', () async {
    final refresh = Completer<http.Response>();
    final h = AuthHarness((r) async {
      if (r.url.path.endsWith('/login')) return ok(bundle());
      if (r.url.path.endsWith('/refresh')) return refresh.future;
      return ok({'user': bundle()['user'], 'session': bundle()['session']});
    });
    await h.auth.login('test@example.com', 'password123');
    h.time = h.time.add(const Duration(minutes: 16));
    final one = h.auth.authorized('GET', '/auth/me');
    final two = h.auth.authorized('GET', '/auth/me');
    await Future<void>.delayed(Duration.zero);
    expect(h.requests.where((r) => r.url.path.endsWith('/refresh')).length, 1);
    refresh.complete(ok(bundle(access: 'access-two', refresh: 'refresh-two')));
    await Future.wait([one, two]);
    expect(h.auth.session!.refreshToken, 'refresh-two');
    expect(
      h.requests
          .where((r) => r.url.path.endsWith('/me'))
          .map((r) => r.headers['Authorization']),
      everyElement('Bearer access-two'),
    );
    h.auth.dispose();
  });

  test(
    'revoked refresh clears secure session and does not fall back to demo',
    () async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/login')
            ? ok(bundle())
            : rejected('SESSION_REVOKED', status: 401),
      );
      await h.auth.login('test@example.com', 'password123');
      h.time = h.time.add(const Duration(minutes: 16));
      await expectLater(
        h.auth.authorized('GET', '/auth/me'),
        throwsA(isA<AuthFailure>()),
      );
      expect(h.auth.session, isNull);
      expect(h.store.value, isNull);
      h.auth.dispose();
    },
  );

  test(
    'logout during refresh prevents a late response restoring the account',
    () async {
      final refresh = Completer<http.Response>();
      final h = AuthHarness((r) async {
        if (r.url.path.endsWith('/login')) return ok(bundle());
        if (r.url.path.endsWith('/refresh')) return refresh.future;
        return ok({'message': 'Logged out'});
      });
      await h.auth.login('test@example.com', 'password123');
      h.time = h.time.add(const Duration(minutes: 16));
      final pending = h.auth.authorized('GET', '/auth/me');
      await Future<void>.delayed(Duration.zero);
      await h.auth.logout();
      refresh.complete(
        ok(bundle(access: 'access-two', refresh: 'refresh-two')),
      );
      await expectLater(pending, throwsA(isA<AuthFailure>()));
      expect(h.auth.session, isNull);
      expect(h.store.value, isNull);
      h.auth.dispose();
    },
  );

  test(
    'restore validates stored user with backend, not just token presence',
    () async {
      final h = AuthHarness(
        (r) async =>
            ok({'user': bundle()['user'], 'session': bundle()['session']}),
      );
      h.store.value = AuthSession.fromResponse(bundle(), testNow).encode();
      expect(await h.auth.restore(), isTrue);
      expect(h.requests.single.url.path.endsWith('/me'), isTrue);
      h.auth.dispose();
    },
  );

  test('background refresh does not count as foreground activity', () async {
    final h = AuthHarness(
      (r) async => r.url.path.endsWith('/activity')
          ? ok({'message': 'Recorded'})
          : ok(bundle(access: 'rotated', refresh: 'rotated-refresh')),
    );
    await h.auth.login('test@example.com', 'password123');
    await h.auth.foregroundActivity(opened: true);
    h.time = h.time.add(const Duration(minutes: 16));
    await h.auth.authorized('GET', '/auth/me');
    await h.auth.foregroundActivity();
    expect(h.requests.where((r) => r.url.path.endsWith('/activity')).length, 2);
    await h.auth.foregroundActivity();
    expect(h.requests.where((r) => r.url.path.endsWith('/activity')).length, 2);
    h.auth.dispose();
  });

  test(
    'storage failure revokes acquired session and prevents sign in',
    () async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/logout')
            ? ok({'message': 'Done'})
            : ok(bundle()),
      );
      h.store.failWrite = true;
      await expectLater(
        h.auth.login('test@example.com', 'password123'),
        throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'STORAGE')),
      );
      expect(h.auth.session, isNull);
      expect(h.requests.last.url.path.endsWith('/logout'), isTrue);
      h.auth.dispose();
    },
  );

  test(
    'API error preserves cooldown without exposing raw response internals',
    () async {
      final h = AuthHarness(
        (r) async => rejected('OTP_COOLDOWN', status: 429, retryAfter: 42),
      );
      try {
        await h.auth.requestLoginCode('test@example.com');
        fail('expected failure');
      } on AuthFailure catch (e) {
        expect(e.retryAfter, 42);
        expect(e.message, isNot(contains('secret')));
        expect(e.toString(), isNot(contains('test@example')));
      }
      h.auth.dispose();
    },
  );

  test('non-json proxy error fails safely', () async {
    final h = AuthHarness(
      (r) async => http.Response('<html>upstream error</html>', 502),
    );
    await expectLater(
      h.auth.login('test@example.com', 'password123'),
      throwsA(isA<AuthFailure>()),
    );
    expect(h.store.value, isNull);
    h.auth.dispose();
  });

  test('uncertain exchange cannot replay one-use completion code', () async {
    final h = AuthHarness(
      (r) async => r.url.path.endsWith('/native/start')
          ? ok(startData())
          : throw http.ClientException('offline'),
    );
    final pending = await h.auth.authorize('google');
    await expectLater(h.auth.exchange(pending), throwsA(isA<AuthFailure>()));
    await expectLater(h.auth.exchange(pending), throwsA(isA<AuthFailure>()));
    expect(h.requests.length, 2);
    h.auth.dispose();
  });
  test(
    'logout waits for a slow secure write and cannot resurrect login',
    () async {
      final h = AuthHarness(
        (r) async => r.url.path.endsWith('/logout')
            ? ok({'message': 'Done'})
            : ok(bundle()),
      );
      h.store.beforeWrite = Completer<void>();
      final login = h.auth.login('test@example.com', 'password123');
      final rejectedLogin = expectLater(login, throwsA(isA<AuthFailure>()));
      await Future<void>.delayed(Duration.zero);
      final logout = h.auth.logout();
      h.store.beforeWrite!.complete();
      await rejectedLogin;
      await logout;
      expect(h.store.value, isNull);
      expect(h.auth.session, isNull);
      h.auth.dispose();
    },
  );
  test('live backend INVALID_OTP is an actionable code-entry error', () {
    expect(
      const AuthFailure('INVALID_OTP', status: 400).message,
      contains('code is incorrect or expired'),
    );
  });
}
