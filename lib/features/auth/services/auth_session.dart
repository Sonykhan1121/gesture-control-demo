import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_api.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
    required this.sessionId,
  });
  final String accessToken, refreshToken, sessionId;
  final DateTime expiresAt;
  final Map<String, dynamic> user;
  String get userId => user['id'] as String;
  String get name => (user['name'] as String?)?.trim().isNotEmpty == true
      ? user['name'] as String
      : 'User';

  factory AuthSession.fromResponse(Map<String, dynamic> data, DateTime now) {
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    final user = data['user'];
    final session = data['session'];
    final seconds = data['expiresIn'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        user is! Map<String, dynamic> ||
        user['id'] is! String ||
        (user['id'] as String).isEmpty ||
        session is! Map ||
        session['id'] is! String ||
        seconds is! int ||
        seconds <= 0) {
      throw const AuthFailure('INVALID_RESPONSE');
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: now.add(Duration(seconds: seconds)),
      user: user,
      sessionId: session['id'] as String,
    );
  }

  String encode() => jsonEncode({
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'user': user,
    'sessionId': sessionId,
  });

  factory AuthSession.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    final user = Map<String, dynamic>.from(data['user'] as Map);
    if (user['id'] is! String || (user['id'] as String).isEmpty) {
      throw const FormatException();
    }
    final result = AuthSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int),
      user: user,
      sessionId: data['sessionId'] as String,
    );
    if (result.accessToken.isEmpty ||
        result.refreshToken.isEmpty ||
        result.sessionId.isEmpty) {
      throw const FormatException();
    }
    return result;
  }
}

abstract interface class AuthSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  static const _key = 'gister.native.session.v1';
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) async {
    await _storage.write(key: _key, value: value);
    if (await _storage.read(key: _key) != value) {
      throw const AuthFailure('STORAGE');
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
