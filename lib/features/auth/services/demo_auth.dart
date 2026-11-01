import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_api.dart';
import 'social_browser.dart';

/// Offline presentation adapter. This is not an authentication/security service.
/// Never use real account credentials in this portfolio demo.
class DemoAuthApi extends AuthApi {
  DemoAuthApi(this.preferences);
  final SharedPreferences preferences;
  static const email = 'demo@example.com';
  static const password = 'Demo1234!';
  static const otp = '12345678';
  static const _accountsKey = 'portfolio.accounts.v1';
  final _pending = <String, Map<String, dynamic>>{};
  final _social = <String, Map<String, String>>{};

  Map<String, dynamic> get _accounts =>
      jsonDecode(preferences.getString(_accountsKey) ?? '{}')
          as Map<String, dynamic>;
  String _digest(String email, String password) =>
      sha256.convert(utf8.encode('$email|$password')).toString();
  Future<void> _save(String email, String name, String password) async {
    final accounts = _accounts;
    accounts[email] = {
      'name': name,
      'passwordHash': _digest(email, password),
      'revision': _random(),
    };
    await preferences.setString(_accountsKey, jsonEncode(accounts));
  }

  Future<void> initialize() async {
    if (!_accounts.containsKey(email)) {
      await _save(email, 'Demo Explorer', password);
    }
  }

  String _random() => base64Url
      .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  List<String> get _revoked =>
      preferences.getStringList('portfolio.revoked') ?? [];
  Map<String, dynamic> _identity(String? token, String kind) {
    try {
      if (token == null || !token.startsWith('demo.$kind.')) {
        throw const FormatException();
      }
      final value =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(token.substring('demo.$kind.'.length)),
                  ),
                ),
              )
              as Map<String, dynamic>;
      if (!_accounts.containsKey(value['email']) ||
          _accounts[value['email']]['revision'] != value['revision'] ||
          _revoked.contains(value['session'])) {
        throw const FormatException();
      }
      return value;
    } catch (_) {
      throw const AuthFailure('SESSION_EXPIRED', status: 401);
    }
  }

  Map<String, dynamic> _bundle(String email, [String? session]) {
    final id = session ?? _random();
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'email': email,
          'session': id,
          'revision': _accounts[email]['revision'],
        }),
      ),
    );
    return {
      'accessToken': 'demo.access.$payload',
      'refreshToken': 'demo.refresh.$payload',
      'expiresIn': 3600,
      'user': {
        'id': email,
        'email': email,
        'name': _accounts[email]['name'],
        'emailVerified': true,
      },
      'session': {'id': id},
    };
  }

  void _code(Map<String, dynamic> body) {
    if (body['otp'] != otp) throw const AuthFailure('INVALID_OTP');
  }

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final data = body ?? {};
    final address = (data['email'] as String? ?? '').trim().toLowerCase();
    if (path == '/auth/register/request-otp') {
      if (_accounts.containsKey(address)) {
        throw const AuthFailure('EMAIL_ALREADY_EXISTS');
      }
      _pending[address] = Map.of(data);
      return {};
    }
    if (path == '/auth/register/verify') {
      _code(data);
      final pending = _pending.remove(address);
      if (pending == null) throw const AuthFailure('FLOW_EXPIRED');
      await _save(
        address,
        pending['name'] as String,
        pending['password'] as String,
      );
      return {};
    }
    if (path == '/auth/login') {
      final account = _accounts[address];
      if (account == null ||
          account['passwordHash'] !=
              _digest(address, data['password'] as String? ?? '')) {
        throw const AuthFailure('INVALID_CREDENTIALS');
      }
      return _bundle(address);
    }
    if (path == '/auth/login/otp/request' ||
        path == '/auth/password/reset/request') {
      if (!_accounts.containsKey(address)) {
        throw const AuthFailure('EMAIL_NOT_REGISTERED');
      }
      return {};
    }
    if (path == '/auth/login/otp/verify') {
      _code(data);
      if (!_accounts.containsKey(address)) {
        throw const AuthFailure('EMAIL_NOT_REGISTERED');
      }
      return _bundle(address);
    }
    if (path == '/auth/password/reset/confirm') {
      _code(data);
      final account = _accounts[address];
      if (account == null) throw const AuthFailure('EMAIL_NOT_REGISTERED');
      await _save(
        address,
        account['name'] as String,
        data['newPassword'] as String,
      );
      return {};
    }
    if (RegExp(
      r'^/auth/social/(google|facebook)/native/(start|link)$',
    ).hasMatch(path)) {
      final provider = path.split('/')[3];
      final state = _random();
      final linkedEmail = path.endsWith('/link')
          ? _identity(accessToken, 'access')['email'] as String
          : 'demo.$provider@example.com';
      final code = 'demo-$provider-$state';
      _social[code] = {
        'email': linkedEmail,
        'challenge': data['codeChallenge'] as String,
      };
      return {
        'state': state,
        'authorizationUrl': Uri.https(
          provider == 'google' ? 'accounts.google.com' : 'www.facebook.com',
          '/demo',
          {'state': state, 'demo_code': code},
        ).toString(),
      };
    }
    if (path == '/auth/social/exchange') {
      final pending = _social.remove(data['code']);
      final challenge = base64Url
          .encode(
            sha256.convert(utf8.encode(data['codeVerifier'] as String)).bytes,
          )
          .replaceAll('=', '');
      if (pending == null || pending['challenge'] != challenge) {
        throw const AuthFailure('OAUTH_CODE_INVALID');
      }
      final address = pending['email']!;
      if (!_accounts.containsKey(address)) {
        await _save(
          address,
          'Demo ${address.contains('google') ? 'Google' : 'Facebook'} User',
          _random(),
        );
      }
      return _bundle(address);
    }
    if (path == '/auth/refresh') {
      final user = _identity(data['refreshToken'] as String?, 'refresh');
      return _bundle(user['email'] as String, user['session'] as String);
    }
    if (path == '/auth/me') {
      final user = _identity(accessToken, 'access');
      return _bundle(user['email'] as String, user['session'] as String);
    }
    if (path == '/auth/logout') {
      final user = _identity(accessToken, 'access');
      await preferences.setStringList('portfolio.revoked', [
        ..._revoked,
        user['session'] as String,
      ]);
      return {};
    }
    if (path == '/auth/activity') {
      _identity(accessToken, 'access');
      return {};
    }
    throw const AuthFailure('UNSUPPORTED');
  }
}

/// Produces an in-process callback; never opens a provider or browser.
class DemoSocialBrowser implements SocialBrowser {
  @override
  Future<Uri> authenticate(Uri url) async =>
      Uri.parse(gisterNativeCallback).replace(
        queryParameters: {
          'state': url.queryParameters['state'],
          'code': url.queryParameters['demo_code'],
          'social_status': 'ready',
        },
      );
}
