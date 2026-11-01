import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/auth/services/auth_api.dart';
import 'package:hand_gesture/features/auth/services/social_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_web_auth_2');
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final provider in ['Google', 'Facebook']) {
      test(
        '$provider retains browser session on $platform without changing the authorization request',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final calls = <MethodCall>[];
          var cancel = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                calls.add(call);
                if (cancel) throw PlatformException(code: 'CANCELED');
                return '$gisterNativeCallback?social_status=ready&code=test';
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          final browser = NativeSocialBrowser();
          final url = Uri.https(
            provider == 'Google' ? 'accounts.google.com' : 'www.facebook.com',
            provider == 'Google' ? '/o/oauth2/v2/auth' : '/v26.0/dialog/oauth',
            {
              'state': 'test-state',
              'redirect_uri': 'https://example.com/provider/callback',
              'response_type': 'code',
              'code_challenge': 'test-challenge',
            },
          );
          await browser.authenticate(url);
          await browser.authenticate(url);
          for (final call in calls) {
            expect(call.arguments['options']['preferEphemeral'], isFalse);
            expect(call.arguments['url'], url.toString());
            expect(
              call.arguments['callbackUrlScheme'],
              'com.sonykhan.gesturedemo',
            );
          }
          cancel = true;
          await expectLater(
            browser.authenticate(url),
            throwsA(
              isA<AuthFailure>().having((e) => e.code, 'code', 'CANCELLED'),
            ),
          );
        },
      );
    }
  }
}
