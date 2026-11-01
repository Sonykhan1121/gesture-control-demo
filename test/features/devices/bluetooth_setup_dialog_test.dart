import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/devices/bluetooth_setup_dialog.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Discovery extends DeviceDiscovery {
  BluetoothSetupIssue? issue;
  bool waiting = false, active = false;
  int starts = 0, stops = 0;
  @override
  BluetoothSetupIssue? get setupIssue => issue;
  @override
  bool get waitingForBluetooth => waiting;
  @override
  bool get scanning => active;
  @override
  String? get error => issue == null ? null : 'Old radio error';
  @override
  List<DiscoveredDevice> get devices => [];
  @override
  Future<void> restart() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  void update({
    BluetoothSetupIssue? issue,
    bool waiting = false,
    bool scanning = false,
  }) {
    this.issue = issue;
    this.waiting = waiting;
    active = scanning;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'Add Device guides radio/permission separately and automatically shows scanning when ready',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final discovery = _Discovery()..issue = BluetoothSetupIssue.poweredOff;
      final controller = GestureController(
        await SharedPreferences.getInstance(),
        discovery: discovery,
      );
      controller.chooseConnection('Auto');
      await tester.pumpWidget(GestureApp(controller: controller));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bluetooth-setup-dialog')),
        findsOneWidget,
      );
      expect(find.text('Open Control Center'), findsOneWidget);
      expect(find.text('Make Bluetooth blue'), findsOneWidget);
      expect(find.text('Open app settings'), findsNothing);
      expect(find.text('Old radio error'), findsNothing);
      final primary = find.byKey(const ValueKey('bluetooth-setup-primary'));
      await tester.ensureVisible(primary);
      await tester.tap(primary);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bluetooth-setup-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('bluetooth-setup-card')),
        findsOneWidget,
      );
      expect(
        discovery.stops,
        0,
        reason: 'Dismissing help keeps automatic readiness watching',
      );
      await tester.tap(find.byKey(const ValueKey('bluetooth-show-help')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bluetooth-setup-dialog')),
        findsOneWidget,
      );
      discovery.update(issue: BluetoothSetupIssue.permissionDenied);
      await tester.pump();
      expect(find.text('Open Control Center'), findsNothing);
      expect(find.text('Allow Bluetooth'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Open app settings'),
        findsOneWidget,
      );
      discovery.update(scanning: true);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bluetooth-setup-dialog')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('bluetooth-setup-card')), findsNothing);
      expect(
        find.text('Searching for nearby Bluetooth device'),
        findsOneWidget,
      );
      expect(
        discovery.starts,
        1,
        reason: 'UI readiness transitions must not request refresh',
      );
      discovery.update(waiting: true, scanning: true);
      await tester.pump();
      expect(find.text('Getting Bluetooth ready'), findsOneWidget);
      expect(find.text('Searching for nearby Bluetooth device'), findsNothing);
      discovery.update();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission button opens app settings once and gives a manual fallback on failure',
    (tester) async {
      final gate = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BluetoothSetupDialog(
            issue: BluetoothSetupIssue.permissionDenied,
            onLater: () {},
            openSettings: () {
              calls++;
              return gate.future;
            },
          ),
        ),
      );
      final primary = find.byKey(const ValueKey('bluetooth-setup-primary'));
      await tester.ensureVisible(primary);
      await tester.tap(primary);
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<FilledButton>(primary).onPressed, isNull);
      gate.complete(false);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bluetooth-settings-error')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(874, 402)]) {
    for (final issue in BluetoothSetupIssue.values) {
      testWidgets('$issue instructions scroll on $size with large text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.5),
              ),
              child: BluetoothSetupDialog(
                issue: issue,
                onLater: () => dismissed = true,
                openSettings: () async => true,
              ),
            ),
          ),
        );
        final button = issue == BluetoothSetupIssue.permissionDenied
            ? find.text('Not now')
            : find.byKey(const ValueKey('bluetooth-setup-primary'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        expect(dismissed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
