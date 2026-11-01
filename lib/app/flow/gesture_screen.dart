import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/auth/auth_screen.dart';
import 'package:hand_gesture/features/devices/device_screens.dart';
import 'package:hand_gesture/features/setup/setup_screens.dart';
import 'package:hand_gesture/features/tutorials/tutorial_screen.dart';
import 'package:hand_gesture/features/tutorials/face_tutorial_screen.dart';
import 'package:hand_gesture/features/home/control_screen.dart';
import 'package:hand_gesture/features/settings/settings_screens.dart';

class GestureScreen extends StatelessWidget {
  const GestureScreen({super.key, this.authUiPreview = false});
  final bool authUiPreview;
  @override
  Widget build(BuildContext context) {
    // Android can report an empty view before the first window metrics arrive.
    // Canvas pages divide by their scale, so wait for a usable viewport.
    if (MediaQuery.sizeOf(context).isEmpty) return const SizedBox.shrink();
    final c = context.watch<GestureController>();
    if (c.restoringAuth) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return switch (c.page) {
      FlowPage.splash || FlowPage.login || FlowPage.createAccount => AuthScreen(
        key: ValueKey(c.page),
        page: c.page,
        authUiPreview: authUiPreview,
      ),
      FlowPage.home ||
      FlowPage.connect => DeviceScreens(key: ValueKey(c.page), page: c.page),
      FlowPage.camera ||
      FlowPage.hand => SetupScreens(key: ValueKey(c.page), page: c.page),
      FlowPage.tutorial || FlowPage.tutorialCompleted => const TutorialScreen(),
      FlowPage.control => const ControlScreen(),
      FlowPage.faceTutorial => const FaceTutorialScreen(),
      FlowPage.settings ||
      FlowPage.selectMode ||
      FlowPage.reactions ||
      FlowPage.tutorialMenu ||
      FlowPage.about => SettingsScreens(key: ValueKey(c.page), page: c.page),
    };
  }
}
