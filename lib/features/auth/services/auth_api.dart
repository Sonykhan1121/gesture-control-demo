import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Non-routable placeholder. Network auth is disabled in this portfolio copy.
const gisterApiBase = 'https://demo.invalid';
const gisterNativeCallback = 'com.sonykhan.gesturedemo://auth/callback';

class AuthFailure implements Exception {
  const AuthFailure(this.code, {this.status = 0, this.retryAfter});
  final String code;
  final int status;
  final int? retryAfter;

  String get message => switch (code) {
    'CANCELLED' => 'Sign-in cancelled.',
    'NATIVE_FLOW_UNAVAILABLE' || 'PROVIDER_UNAVAILABLE' =>
      'Social sign-in is temporarily unavailable. Please try again later.',
    'ACCOUNT_LINK_REQUIRED' =>
      'Log in to your existing account to link this provider.',
    'SOCIAL_EMAIL_REQUIRED' =>
      'Please allow access to your email in Facebook and try again.',
    'INVALID_CREDENTIALS' ||
    'AUTH_INVALID_CREDENTIALS' ||
    'LOGIN_FAILED' => 'The email or password is incorrect.',
    'EMAIL_NOT_VERIFIED' => 'Please verify your existing account email first.',
    'EMAIL_NOT_REGISTERED' =>
      'No account uses this email. Please create an account first.',
    'OTP_ATTEMPTS_EXCEEDED' || 'OTP_MAX_ATTEMPTS' =>
      'Too many incorrect codes. Please request a new code.',
    'EMAIL_ALREADY_EXISTS' || 'EMAIL_ALREADY_REGISTERED' =>
      'This email already has an account. Please log in.',
    'ACCOUNT_INACTIVE' =>
      'This account is unavailable. Please contact support.',
    'OAUTH_STATE_INVALID' ||
    'CALLBACK_INVALID' => 'Sign-in could not be verified. Please start again.',
    'OAUTH_CODE_INVALID' ||
    'FLOW_EXPIRED' => 'This sign-in attempt has expired. Please start again.',
    'INVALID_OTP' ||
    'OTP_INVALID' ||
    'OTP_EXPIRED' ||
    'OTP_INVALID_OR_EXPIRED' =>
      'That code is incorrect or expired. Please try again or request a new code.',
    'OTP_COOLDOWN' => 'Please wait before requesting another code.',
    'RECENT_LOGIN_REQUIRED' =>
      'Please log in again before linking this account.',
    'NETWORK' => 'Unable to connect. Check your connection and try again.',
    'STORAGE' => 'Unable to save your secure session. Please try again.',
    'BUSY' => 'A sign-in is already in progress.',
    'UNSUPPORTED' => 'Please use the Android or iPhone app to sign in.',
    'SESSION_EXPIRED' => 'Your session has expired. Please log in again.',
    _ when status == 401 =>
      'The email, password or session is invalid. Please try again.',
    _ when status == 429 => 'Too many attempts. Please wait and try again.',
    _ => 'Unable to complete sign-in. Please try again.',
  };

  // Deliberately excludes response bodies, URLs, tokens, passwords and codes.
  @override
  String toString() => 'AuthFailure($code, $status)';
}

class AuthApi {
  AuthApi({http.Client? client, this.baseUrl = gisterApiBase})
    : _client = client ?? _OfflineClient();
  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..followRedirects = false
        ..headers.addAll({
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-Client-Type': 'native',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        });
      if (method != 'GET') request.body = jsonEncode(body ?? {});
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 20));
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(utf8.decode(response.bodyBytes));
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        /* Handle non-JSON proxy errors below. */
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded?['success'] != true) {
        final error = decoded?['error'];
        throw AuthFailure(
          error is Map && error['code'] is String
              ? error['code'] as String
              : 'SERVICE_UNAVAILABLE',
          status: response.statusCode,
          retryAfter: int.tryParse(response.headers['retry-after'] ?? ''),
        );
      }
      final data = decoded?['data'];
      if (data is! Map<String, dynamic>) {
        throw const AuthFailure('INVALID_RESPONSE');
      }
      return data;
    } on AuthFailure {
      rethrow;
    } on Exception {
      throw const AuthFailure('NETWORK');
    }
  }

  void close() => _client.close();
}

// Default transport cannot contact any server in the portfolio copy. Tests may
// inject a MockClient; main.dart injects the local DemoAuthApi adapter.
class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException(
      'Network authentication is disabled in this demo.',
    );
  }
}
