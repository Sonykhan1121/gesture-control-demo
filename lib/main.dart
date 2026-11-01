import 'package:flutter/material.dart';
import 'features/auth/services/demo_auth.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/auth/services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final api = DemoAuthApi(preferences);
  await api.initialize();
  final controller = GestureController(
    preferences,
    auth: AuthService(api: api, browser: DemoSocialBrowser()),
  );
  runApp(GestureApp(controller: controller));
  unawaited(controller.restoreAuth());
}
