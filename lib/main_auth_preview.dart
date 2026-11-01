import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';

/// Separate demo entry point; production login and saved setup stay untouched.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This demo's profile/session changes live only in memory, never on the phone.
  // Intentional use in this isolated demo executable; normal main.dart never
  // replaces the real preferences platform store.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final controller = GestureController(await SharedPreferences.getInstance());
  controller.open(FlowPage.login);
  runApp(GestureApp(controller: controller, authUiPreview: true));
}
