import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';

class _Discovery extends DeviceDiscovery {
  @override
  List<DiscoveredDevice> get devices => [];
  @override
  bool get scanning => false;
  @override
  String? get error => null;
  @override
  Future<void> restart() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  for (final size in [
    const Size(402, 874),
    const Size(874, 402),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'custom colors preview, cancel, save and reopen at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final c = GestureController(prefs, discovery: _Discovery());
        c.open(FlowPage.reactions);
        await tester.pumpWidget(GestureApp(controller: c));
        await tester.pumpAndSettle();
        Future<void> tapKey(String key) async {
          final f = find.byKey(ValueKey(key));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        Future<void> enter(String value) async {
          await tester.enterText(
            find.byKey(const ValueKey('color-hex')),
            value,
          );
          await tester.pumpAndSettle();
        }

        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('add-reaction-color')))
              .dx,
          greaterThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('reaction-color-0')))
                .dx,
          ),
        );
        await tapKey('add-reaction-color');
        await tapKey('use-custom-color');
        expect(
          find.byKey(const ValueKey('custom-reaction-swatch')),
          findsNothing,
        );
        await tapKey('add-reaction-color');
        await enter('#ff5500');
        expect(c.faceColor, 0xffbbcff9);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('custom-reaction-swatch')),
          findsNothing,
        );
        await tapKey('add-reaction-color');
        await enter('#ff5500');
        await tapKey('use-custom-color');
        expect(
          find.byKey(const ValueKey('custom-reaction-swatch')),
          findsOneWidget,
        );
        final customRect = tester.getRect(
          find.byKey(const ValueKey('custom-reaction-swatch')),
        );
        final plusRect = tester.getRect(
          find.byKey(const ValueKey('add-reaction-color')),
        );
        expect(plusRect.width, closeTo(customRect.width, .1));
        if ((plusRect.top - customRect.top).abs() < 1) {
          expect(
            plusRect.left - customRect.right,
            greaterThanOrEqualTo(customRect.width * .26),
          );
        } else {
          expect(
            plusRect.top - customRect.bottom,
            greaterThanOrEqualTo(customRect.height * .26),
          );
        }
        final active = find.byKey(const ValueKey('custom-reaction-swatch'));
        final palette = find
            .ancestor(of: active, matching: find.byType(Wrap))
            .first;
        expect(tester.getTopLeft(active), tester.getTopLeft(palette));
        expect(
          find.descendant(of: active, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        await tapKey('add-background-color');
        await enter('#30204a');
        await tapKey('use-custom-color');
        final save = find.text('Save');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(prefs.getInt('gesture.faceColor'), 0xffff5500);
        expect(prefs.getInt('gesture.faceBackground'), 0xff30204a);
        final restored = GestureController(prefs, discovery: _Discovery());
        restored.open(FlowPage.reactions);
        await tester.pumpWidget(
          GestureApp(key: UniqueKey(), controller: restored),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('custom-reaction-swatch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('custom-background-swatch')),
          findsOneWidget,
        );
        for (final key in [
          'custom-reaction-swatch',
          'custom-background-swatch',
        ]) {
          final selected = find.byKey(ValueKey(key));
          final palette = find
              .ancestor(of: selected, matching: find.byType(Wrap))
              .first;
          expect(tester.getTopLeft(selected), tester.getTopLeft(palette));
          expect(
            find.descendant(of: selected, matching: find.byIcon(Icons.check)),
            findsOneWidget,
          );
        }
        await tapKey('add-background-color');
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('color-hex')))
              .controller!
              .text,
          '#30204A',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        restored.dispose();
      },
      skip: !const bool.fromEnvironment('LAZIVOO_CUSTOM_COLORS'),
    );
    testWidgets(
      'hidden add controls retain selected colors at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'gesture.faceColor': 0xff955ace,
          'gesture.faceBackground': 0xff20283a,
        });
        final prefs = await SharedPreferences.getInstance();
        final c = GestureController(prefs, discovery: _Discovery());
        c.open(FlowPage.reactions);
        await tester.pumpWidget(GestureApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('add-reaction-color')), findsNothing);
        expect(
          find.byKey(const ValueKey('add-background-color')),
          findsNothing,
        );
        for (final key in [
          'custom-reaction-swatch',
          'custom-background-swatch',
        ]) {
          final selected = find.byKey(ValueKey(key));
          final palette = find
              .ancestor(of: selected, matching: find.byType(Wrap))
              .first;
          expect(tester.getTopLeft(selected), tester.getTopLeft(palette));
          expect(
            find.descendant(of: selected, matching: find.byIcon(Icons.check)),
            findsOneWidget,
          );
        }
        final save = find.text('Save');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(prefs.getInt('gesture.faceColor'), 0xff955ace);
        expect(prefs.getInt('gesture.faceBackground'), 0xff20283a);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      },
      skip: const bool.fromEnvironment('LAZIVOO_CUSTOM_COLORS'),
    );
  }
}
