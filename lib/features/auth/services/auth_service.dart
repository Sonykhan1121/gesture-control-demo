import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'social_browser.dart';

class PendingSocial {
  PendingSocial._(
    this.provider,
    this.state,
    this._verifier,
    this.code,
    this.needsEmail,
    this._createdAt,
    this._epoch,
    this._linkSession,
    this._generation,
  );
  final String provider, state, _verifier;
  String code;
  bool needsEmail;
  final DateTime _createdAt;
  final int _epoch;
  final AuthSession? _linkSession;
  final int _generation;
  bool _exchanging = false;
}

/// Native body-token flow only. Temporary proof keys never enter storage/logs.
class AuthService extends ChangeNotifier {
  AuthService({
    AuthApi? api,
    AuthSessionStore? store,
    SocialBrowser? browser,
    DateTime Function()? now,
    String Function()? verifierFactory,
  }) : api = api ?? AuthApi(),
       store = store ?? SecureAuthSessionStore(),
       browser = browser ?? NativeSocialBrowser(),
       now = now ?? DateTime.now,
       _verifierFactory = verifierFactory ?? _newVerifier;
  final AuthApi api;
  final AuthSessionStore store;
  final SocialBrowser browser;
  final DateTime Function() now;
  final String Function() _verifierFactory;
  AuthSession? _session;
  AuthSession? get session => _session;
  PendingSocial? _pending;
  bool _authorizing = false;
  Future<AuthSession>? _refreshing;
  DateTime? _lastActivity;
  bool _activityInFlight = false;
  int _epoch = 0;
  int _attemptGeneration = 0;
  bool _disposed = false;
  Future<void> _storeTail = Future<void>.value();

  // Serialize secure writes/clears so a slow, cancelled login cannot overwrite
  // a later logout or a different successful login.
  Future<T> _withStore<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _storeTail = _storeTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  String get deviceName => defaultTargetPlatform == TargetPlatform.iOS
      ? 'lazivoo iPhone'
      : 'lazivoo Android';

  Future<AuthSession> login(String email, String password) async {
    final epoch = _epoch;
    final data = await api.request(
      'POST',
      '/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'deviceName': deviceName,
      },
    );
    final result = AuthSession.fromResponse(data, now());
    await _commit(result, epoch);
    return result;
  }

  Future<void> requestRegistration(
    String name,
    String email,
    String password,
  ) async {
    await api.request(
      'POST',
      '/auth/register/request-otp',
      body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
  }

  Future<void> verifyRegistration(String email, String otp) async {
    await api.request(
      'POST',
      '/auth/register/verify',
      body: {'email': email.trim().toLowerCase(), 'otp': otp},
    );
  }

  Future<void> requestLoginCode(String email) async {
    await api.request(
      'POST',
      '/auth/login/otp/request',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  Future<AuthSession> verifyLoginCode(
    String email,
    String otp, {
    bool temporary = false,
  }) async {
    final epoch = _epoch;
    final data = await api.request(
      'POST',
      '/auth/login/otp/verify',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp,
        'deviceName': deviceName,
      },
    );
    final result = AuthSession.fromResponse(data, now());
    if (!temporary) await _commit(result, epoch);
    return result;
  }

  Future<void> requestPasswordReset(String email) async {
    await api.request(
      'POST',
      '/auth/password/reset/request',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  Future<void> resetPassword(String email, String otp, String password) async {
    await api.request(
      'POST',
      '/auth/password/reset/confirm',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp,
        'newPassword': password,
      },
    );
    if (_session?.user['email'] == email.trim().toLowerCase()) await _expire();
  }

  static String _newVerifier() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  Future<PendingSocial> authorize(
    String provider, {
    AuthSession? linkSession,
    bool chooseGoogleAccount = false,
  }) async {
    if (!const ['google', 'facebook'].contains(provider)) {
      throw const AuthFailure('PROVIDER_UNAVAILABLE');
    }
    if (_authorizing) throw const AuthFailure('BUSY');
    _authorizing = true;
    _pending = null;
    final epoch = _epoch;
    final generation = ++_attemptGeneration;
    final started = now();
    try {
      final verifier = _verifierFactory();
      final data = await api.request(
        'POST',
        '/auth/social/$provider/native/${linkSession == null ? 'start' : 'link'}',
        body: {'codeChallenge': challengeFor(verifier)},
        accessToken: linkSession?.accessToken,
      );
      final state = data['state'];
      if (generation != _attemptGeneration || epoch != _epoch) {
        throw const AuthFailure('CANCELLED');
      }
      final value = data['authorizationUrl'];
      if (state is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(state) ||
          value is! String) {
        throw const AuthFailure('INVALID_RESPONSE');
      }
      final url = Uri.tryParse(value);
      final validHost = provider == 'google'
          ? url?.host == 'accounts.google.com'
          : url?.host == 'facebook.com' ||
                (url?.host.endsWith('.facebook.com') ?? false);
      if (url == null ||
          url.scheme != 'https' ||
          !validHost ||
          url.userInfo.isNotEmpty ||
          url.hasPort && url.port != 443) {
        throw const AuthFailure('INVALID_RESPONSE');
      }
      var browserUrl = url;
      if (provider == 'google' && chooseGoogleAccount) {
        // Only the presentation preference changes. Keep the backend's fresh
        // state, PKCE, nonce, scopes and callback intact for this attempt.
        final query = Map<String, dynamic>.from(url.queryParametersAll);
        final prompts =
            (url.queryParametersAll['prompt'] ?? [])
                .expand((value) => value.split(RegExp(r'\s+')))
                .where((value) => value.isNotEmpty && value != 'none')
                .toSet()
              ..add('select_account');
        query['prompt'] = prompts.join(' ');
        query.remove('login_hint');
        query.remove('authuser');
        browserUrl = url.replace(queryParameters: query);
      } else if (provider == 'facebook') {
        // Match Meta's Android CustomTab dialog host. The www-hosted login
        // continuation can enter Facebook's feed on Android tablets after 2FA.
        // Keep the API version, callback, OAuth parameters and PKCE intact.
        final query = Map<String, dynamic>.from(url.queryParametersAll);
        query['display'] = 'touch';
        browserUrl = url.replace(
          host: defaultTargetPlatform == TargetPlatform.android
              ? 'm.facebook.com'
              : url.host,
          queryParameters: query,
        );
      }
      final callback = await browser.authenticate(browserUrl);
      if (epoch != _epoch || generation != _attemptGeneration) {
        throw const AuthFailure('CANCELLED');
      }
      final expected = Uri.parse(gisterNativeCallback);
      if (callback.scheme != expected.scheme ||
          callback.host != expected.host ||
          callback.path != expected.path ||
          callback.hasPort ||
          callback.userInfo.isNotEmpty) {
        throw const AuthFailure('CALLBACK_INVALID');
      }
      for (final field in ['state', 'code', 'social_status', 'error']) {
        if ((callback.queryParametersAll[field]?.length ?? 0) > 1) {
          throw const AuthFailure('CALLBACK_INVALID');
        }
      }
      if (!_equal(callback.queryParameters['state'] ?? '', state)) {
        throw const AuthFailure('OAUTH_STATE_INVALID');
      }
      final status = callback.queryParameters['social_status'];
      if (status == 'error') {
        throw AuthFailure(callback.queryParameters['error'] ?? 'SOCIAL_FAILED');
      }
      if (status != 'ready' && status != 'email_verification_required') {
        throw const AuthFailure('CALLBACK_INVALID');
      }
      final code = callback.queryParameters['code'];
      if (code == null ||
          code.isEmpty ||
          code.length > 128 ||
          code.contains('#')) {
        throw const AuthFailure('CALLBACK_INVALID');
      }
      final pending = PendingSocial._(
        provider,
        state,
        verifier,
        code,
        status == 'email_verification_required',
        started,
        epoch,
        linkSession,
        generation,
      );
      _pending = pending;
      return pending;
    } finally {
      _authorizing = false;
    }
  }

  static bool _equal(String left, String right) {
    if (left.length != right.length) return false;
    var different = 0;
    for (var i = 0; i < left.length; i++) {
      different |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return different == 0;
  }

  void _checkAttempt(PendingSocial pending) {
    if (!identical(_pending, pending) ||
        pending._epoch != _epoch ||
        pending._generation != _attemptGeneration) {
      throw const AuthFailure('CANCELLED');
    }
    if (now().difference(pending._createdAt) > const Duration(minutes: 15)) {
      throw const AuthFailure('FLOW_EXPIRED');
    }
  }

  Future<void> requestSocialEmail(PendingSocial pending, String email) async {
    _checkAttempt(pending);
    await api.request(
      'POST',
      '/auth/social/email/request',
      body: {
        'code': pending.code,
        'codeVerifier': pending._verifier,
        'email': email.trim().toLowerCase(),
      },
    );
  }

  Future<void> verifySocialEmail(PendingSocial pending, String otp) async {
    _checkAttempt(pending);
    final data = await api.request(
      'POST',
      '/auth/social/email/verify',
      body: {
        'code': pending.code,
        'codeVerifier': pending._verifier,
        'otp': otp,
      },
    );
    _checkAttempt(pending);
    final code = data['code'];
    if (code is! String || code.isEmpty || code.length > 128) {
      throw const AuthFailure('INVALID_RESPONSE');
    }
    pending.code = code;
    pending.needsEmail = false;
  }

  Future<AuthSession> exchange(PendingSocial pending) async {
    _checkAttempt(pending);
    if (pending._exchanging) throw const AuthFailure('BUSY');
    if (pending.needsEmail) {
      throw const AuthFailure('SOCIAL_EMAIL_VERIFICATION_REQUIRED');
    }
    pending._exchanging = true;
    try {
      final data = await api.request(
        'POST',
        '/auth/social/exchange',
        body: {
          'code': pending.code,
          'codeVerifier': pending._verifier,
          'deviceName': defaultTargetPlatform == TargetPlatform.iOS
              ? 'lazivoo iPhone'
              : 'lazivoo Android',
        },
        accessToken: pending._linkSession?.accessToken,
      );
      final session = AuthSession.fromResponse(data, now());
      try {
        _checkAttempt(pending);
      } on AuthFailure {
        await revokeTemporary(session);
        rethrow;
      }
      if (pending._linkSession != null &&
          session.userId != pending._linkSession.userId) {
        throw const AuthFailure('CALLBACK_INVALID');
      }
      // A consumed code is never replayed, including on a storage error.
      _pending = null;
      await _commit(session, pending._epoch, generation: pending._generation);
      return session;
    } on AuthFailure catch (failure) {
      // An uncertain exchange is restarted rather than replaying a one-use code.
      if (failure.code != 'SOCIAL_EMAIL_VERIFICATION_REQUIRED') _pending = null;
      rethrow;
    } finally {
      pending._exchanging = false;
    }
  }

  Future<void> _commit(
    AuthSession session,
    int epoch, {
    int? generation,
  }) async {
    bool cancelled() =>
        _disposed ||
        epoch != _epoch ||
        generation != null && generation != _attemptGeneration;
    if (cancelled()) {
      await revokeTemporary(session);
      throw const AuthFailure('CANCELLED');
    }
    try {
      await _withStore(() async {
        if (cancelled()) throw const AuthFailure('CANCELLED');
        await store.write(session.encode());
        if (cancelled()) {
          await store.clear();
          throw const AuthFailure('CANCELLED');
        }
      });
    } on AuthFailure catch (failure) {
      if (failure.code == 'STORAGE') {
        try {
          await _withStore(store.clear);
        } on Exception {
          /* Fail closed. */
        }
      }
      await revokeTemporary(session);
      rethrow;
    } on Exception {
      try {
        await _withStore(store.clear);
      } on Exception {
        /* Preserve the original storage failure. */
      }
      await revokeTemporary(session);
      throw const AuthFailure('STORAGE');
    }
    if (cancelled()) {
      await revokeTemporary(session);
      throw const AuthFailure('CANCELLED');
    }
    _session = session;
    // Token rotation is not a user interaction.
    if (!_disposed) notifyListeners();
  }

  /// A temporary existing-account session is used only after explicit user login.
  /// It is not persisted until linking succeeds; cancellation revokes it.
  Future<AuthSession> loginForLink(String email, String password) async {
    final data = await api.request(
      'POST',
      '/auth/login',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'deviceName': 'lazivoo account linking',
      },
    );
    return AuthSession.fromResponse(data, now());
  }

  Future<void> revokeTemporary(AuthSession temporary) async {
    try {
      await api.request(
        'POST',
        '/auth/logout',
        accessToken: temporary.accessToken,
      );
    } on AuthFailure {
      /* Cancellation must still close the local flow offline. */
    }
  }

  bool attemptActive(PendingSocial pending) => identical(_pending, pending);

  void cancelAttempt() {
    _attemptGeneration++;
    _pending = null;
  }

  Future<bool> restore() async {
    final epoch = _epoch;
    String? value;
    try {
      value = await _withStore(store.read);
    } on Exception {
      throw const AuthFailure('STORAGE');
    }
    if (value == null || epoch != _epoch || _disposed) return false;
    try {
      _session = AuthSession.decode(value);
    } on Object {
      await _withStore(store.clear);
      return false;
    }
    try {
      final data = await authorized('GET', '/auth/me');
      if (epoch != _epoch) return false;
      final user = data['user'];
      final remoteSession = data['session'];
      if (user is! Map ||
          user['id'] != _session!.userId ||
          remoteSession is! Map ||
          remoteSession['id'] != _session!.sessionId) {
        throw const AuthFailure('INVALID_RESPONSE');
      }
      if (!_disposed) notifyListeners();
      return true;
    } on AuthFailure {
      _session = null;
      rethrow;
    }
  }

  Future<AuthSession> _refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final task = _rotate();
    _refreshing = task;
    // Clear the single-flight future without creating an unhandled error future.
    unawaited(
      task.then<void>(
        (_) {
          _refreshing = null;
        },
        onError: (Object _, StackTrace __) {
          _refreshing = null;
        },
      ),
    );
    return task;
  }

  Future<AuthSession> _rotate() async {
    final previous = _session;
    if (previous == null) throw const AuthFailure('SESSION_EXPIRED');
    final epoch = _epoch;
    try {
      final data = await api.request(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': previous.refreshToken},
      );
      final renewed = AuthSession.fromResponse(data, now());
      if (renewed.userId != previous.userId ||
          renewed.sessionId != previous.sessionId) {
        throw const AuthFailure('INVALID_RESPONSE');
      }
      await _commit(renewed, epoch);
      return renewed;
    } on AuthFailure catch (failure) {
      // A timed-out rotation may have consumed the old credential. Never replay
      // it automatically: the backend treats replay as session theft.
      if (failure.status == 401 ||
          failure.status == 403 ||
          failure.code == 'NETWORK' ||
          failure.code == 'INVALID_RESPONSE') {
        await _expire();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> authorized(String method, String path) async {
    var current = _session;
    if (current == null) throw const AuthFailure('SESSION_EXPIRED');
    if (!now().isBefore(
      current.expiresAt.subtract(const Duration(seconds: 30)),
    )) {
      current = await _refresh();
    }
    final sentToken = current.accessToken;
    try {
      return await api.request(method, path, accessToken: sentToken);
    } on AuthFailure catch (failure) {
      if (failure.status != 401) rethrow;
      final renewed = _session?.accessToken != sentToken && _session != null
          ? _session!
          : await _refresh();
      try {
        return await api.request(
          method,
          path,
          accessToken: renewed.accessToken,
        );
      } on AuthFailure catch (again) {
        if (again.status == 401) await _expire();
        rethrow;
      }
    }
  }

  Future<void> _expire() async {
    _epoch++;
    _pending = null;
    _session = null;
    try {
      await _withStore(store.clear);
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// Called for foreground opens/taps only. No heartbeat or refresh extends idle.
  Future<void> foregroundActivity({bool opened = false}) async {
    if (_session == null || _activityInFlight) return;
    if (!opened &&
        _lastActivity != null &&
        now().difference(_lastActivity!) < const Duration(seconds: 60)) {
      return;
    }
    _activityInFlight = true;
    _lastActivity = now();
    try {
      await authorized('POST', '/auth/activity');
    } on AuthFailure {
      /* The expiry listener handles invalid sessions. Offline taps do not log out. */
    } finally {
      _activityInFlight = false;
    }
  }

  Future<void> logout() async {
    final previous = _session;
    _epoch++;
    _pending = null;
    _session = null;
    try {
      await _withStore(store.clear);
    } finally {
      if (!_disposed) notifyListeners();
      if (previous != null) await revokeTemporary(previous);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    cancelAttempt();
    api.close();
    super.dispose();
  }
}
