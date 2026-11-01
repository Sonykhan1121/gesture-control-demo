import 'package:hand_gesture/shared/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('selected device name survives restarting the controller', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = GestureController(prefs);
    await c.connectDemoDevice(deviceName: 'L01-026f4f(ble)');
    expect(prefs.getString('gesture.device'), 'L01-026f4f(ble)');
    final restored = GestureController(prefs);
    expect(restored.device, 'L01-026f4f(ble)');
    c.dispose();
    restored.dispose();
  });

  for (final size in [
    const Size(402, 874),
    const Size(874, 402),
    const Size(800, 1333),
    const Size(1333, 800),
  ]) {
    testWidgets('device subtitle and full name at $size', (tester) async {
      SharedPreferences.setMockInitialValues({
        'gesture.device': 'L01-026f4f(ble) with a very long device name',
      });
      final c = GestureController(await SharedPreferences.getInstance());
      addTearDown(c.dispose);
      addTearDown(tester.view.reset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      c.open(FlowPage.settings);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-device-name')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('settings-device-name')));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.text(c.device!),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
