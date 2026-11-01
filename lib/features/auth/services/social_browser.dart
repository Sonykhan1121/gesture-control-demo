import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'auth_api.dart';

abstract interface class SocialBrowser {
  Future<Uri> authenticate(Uri url);
}

class NativeSocialBrowser implements SocialBrowser {
  @override
  Future<Uri> authenticate(Uri url) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const AuthFailure('UNSUPPORTED');
    }
    try {
      final value = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: Uri.parse(gisterNativeCallback).scheme,
        // Retain the provider's browser session after login/security checks.
        // Facebook must also retain this session when authorization is retried.
        // Our app session still requires a fresh, validated callback and exchange.
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
      return Uri.parse(value);
    } on PlatformException catch (error) {
      throw AuthFailure(
        error.code == 'CANCELED' || error.code == 'CANCELLED'
            ? 'CANCELLED'
            : 'BROWSER_FAILED',
      );
    } on FormatException {
      throw const AuthFailure('CALLBACK_INVALID');
    }
  }
}
