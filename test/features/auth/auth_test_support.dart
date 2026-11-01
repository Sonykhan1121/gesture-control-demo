import 'dart:convert';
import 'dart:async';

import 'package:hand_gesture/features/auth/services/auth_api.dart';
import 'package:hand_gesture/features/auth/services/auth_service.dart';
import 'package:hand_gesture/features/auth/services/auth_session.dart';
import 'package:hand_gesture/features/auth/services/social_browser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testState = '0123456789012345678901234567890123456789012';
const testVerifier = 'abcdefghijklmnopqrstuvwxyz01234567890123456';
final testNow = DateTime.utc(2026, 10, 28, 12);

Map<String, dynamic> bundle({
  String access = 'access-one',
  String refresh = 'refresh-one',
  String userId = 'user-one',
  String sessionId = 'session-one',
}) => {
  'accessToken': access,
  'refreshToken': refresh,
  'expiresIn': 900,
  'user': {
    'id': userId,
    'name': 'Test User',
    'email': 'test@example.com',
    'emailVerified': true,
  },
  'session': {'id': sessionId},
};

http.Response ok(Map<String, dynamic> data, {int status = 200}) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);
http.Response rejected(String code, {int status = 400, int? retryAfter}) =>
    http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': code, 'message': 'secret server internals'},
      }),
      status,
      headers: {if (retryAfter != null) 'retry-after': '$retryAfter'},
    );
Map<String, dynamic> body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

class MemoryAuthStore implements AuthSessionStore {
  String? value;
  int writes = 0, clears = 0;
  bool failWrite = false;
  Completer<void>? beforeWrite;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrite) throw Exception('storage unavailable');
    await beforeWrite?.future;
    this.value = value;
    writes++;
  }

  @override
  Future<void> clear() async {
    value = null;
    clears++;
  }
}

class TestSocialBrowser implements SocialBrowser {
  int opens = 0;
  Uri? opened;
  Future<Uri> Function(Uri)? respond;
  Uri callback({
    String state = testState,
    String status = 'ready',
    String code = 'completion-one',
    String? error,
  }) => Uri.parse(gisterNativeCallback).replace(
    queryParameters: {
      'state': state,
      'social_status': status,
      'code': code,
      if (error != null) 'error': error,
    },
  );
  @override
  Future<Uri> authenticate(Uri url) async {
    opens++;
    opened = url;
    return respond != null ? respond!(url) : callback();
  }
}

class AuthHarness {
  AuthHarness(Future<http.Response> Function(http.Request) respond) {
    api = AuthApi(
      client: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
    );
    auth = AuthService(
      api: api,
      store: store,
      browser: browser,
      now: () => time,
      verifierFactory: () => testVerifier,
    );
  }
  late final AuthApi api;
  late final AuthService auth;
  final store = MemoryAuthStore();
  final browser = TestSocialBrowser();
  final requests = <http.Request>[];
  DateTime time = testNow;
}

Map<String, dynamic> startData([String provider = 'google']) => {
  'state': testState,
  'authorizationUrl': provider == 'google'
      ? 'https://accounts.google.com/o/oauth2/v2/auth'
      : 'https://www.facebook.com/v20.0/dialog/oauth',
};
