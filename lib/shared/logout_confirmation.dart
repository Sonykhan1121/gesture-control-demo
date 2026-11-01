import 'package:flutter/material.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'app_dialog.dart';

Future<void> confirmLogout(BuildContext context, GestureController c) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: 'Log out?',
      icon: Icons.logout_rounded,
      message: 'Your device setup and control preferences will stay saved.',
      actions: [
        appDialogAction(
          'Cancel',
          () => Navigator.pop(context, false),
          primary: false,
        ),
        appDialogAction('Log out', () => Navigator.pop(context, true)),
      ],
    ),
  );
  if (confirmed == true) await c.logout();
}
