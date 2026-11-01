import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;

class _Discovery extends DeviceDiscovery {
  BluetoothSetupIssue? issue;
  bool active = false;
  @override
  bool get scanning => active;
  @override
  String? get error => null;
  @override
  BluetoothSetupIssue? get setupIssue => issue;
  @override
  List<DiscoveredDevice> get devices => [
    DiscoveredDevice(
      'lazivoo Controller',
      defaultTargetPlatform == TargetPlatform.iOS
          ? '12345678-1234-1234-1234-123456789ABC'
          : 'A4:C1:38:00:00:01',
    ),
  ];
  @override
  Future<void> restart() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  late GestureController c;
  late FakeCameraPlatform camera;
  late CameraPlatform previousCamera;
  late _Discovery discovery;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    discovery = _Discovery();
    c = GestureController(
      await SharedPreferences.getInstance(),
      discovery: discovery,
    );
    previousCamera = CameraPlatform.instance;
    camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });
  tearDown(() {
    c.dispose();
    CameraPlatform.instance = previousCamera;
  });

  void resize(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = size.width > size.height
        ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
        : const FakeViewPadding(top: 54, bottom: 34);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3)),
      );
    }
  }

  testWidgets(
    'every page fits portrait, landscape and short landscape with safe areas',
    (tester) async {
      addTearDown(tester.view.reset);
      final captureDir = Platform.environment['LAZIVOO_LAYOUT_CAPTURE_DIR'];
      if (captureDir != null) {
        for (final font in {
          'Manrope': 'assets/fonts/Manrope.ttf',
          'Poppins': 'assets/fonts/Poppins-Regular.ttf',
          'packages/cupertino_icons/CupertinoIcons':
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            font.key,
          )..addFont(rootBundle.load(font.value))).load();
        }
        await tester.runAsync(
          () => Directory(captureDir).create(recursive: true),
        );
      }
      final boundary = GlobalKey();
      resize(tester, const Size(393, 852));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GestureApp(controller: c),
        ),
      );
      for (final page in FlowPage.values) {
        c.open(page);
        for (final size in [
          const Size(320, 568),
          const Size(375, 667),
          const Size(393, 852),
          const Size(852, 393),
          const Size(568, 320),
          const Size(800, 1333.333333),
          const Size(1333.333333, 800),
          const Size(768, 1024),
          const Size(1024, 768),
        ]) {
          resize(tester, size);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: '$page at $size');
          if (page == FlowPage.connect) {
            final label = defaultTargetPlatform == TargetPlatform.iOS
                ? 'Device ID'
                : 'MAC Address';
            expect(
              find.text('$label: ${discovery.devices.single.address}'),
              findsOneWidget,
            );
          }
          if (size.width < size.height &&
              [
                FlowPage.settings,
                FlowPage.selectMode,
                FlowPage.reactions,
                FlowPage.tutorialMenu,
                FlowPage.about,
                FlowPage.connect,
                FlowPage.camera,
                FlowPage.hand,
                FlowPage.tutorial,
                FlowPage.tutorialCompleted,
                FlowPage.home,
                FlowPage.control,
              ].contains(page)) {
            final header = page == FlowPage.home || page == FlowPage.control
                ? find.byTooltip('Settings')
                : find.byTooltip('Back');
            expect(
              tester.getTopLeft(header.first).dy,
              closeTo(54 + 8, .01),
              reason: '$page header respects the actual status bar at $size',
            );
          }
          if ([
                FlowPage.splash,
                FlowPage.login,
                FlowPage.createAccount,
              ].contains(page) &&
              size.width < size.height) {
            expect(
              tester.getRect(find.byKey(const ValueKey('auth-canvas'))).width,
              closeTo(size.width, .001),
              reason: 'Auth must fill the whole width at $size',
            );
          }
          if (captureDir != null) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$captureDir/${defaultTargetPlatform.name}/${size.width.round()}x${size.height.round()}/${page.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final page in [FlowPage.camera, FlowPage.tutorial]) {
    testWidgets(
      'rotation preserves the live camera and tutorial attempt on $page',
      (tester) async {
        addTearDown(tester.view.reset);
        resize(tester, const Size(393, 852));
        c.open(page);
        await tester.pumpWidget(GestureApp(controller: c));
        await settle(tester);
        final creates = camera.events
            .where((e) => e.startsWith('create:'))
            .length;
        expect(creates, 1);
        final session = c.tutorialSession;
        final guide = page == FlowPage.tutorial
            ? tester.state(find.byType(GestureCameraGuide))
            : null;
        for (final size in [
          const Size(852, 393),
          const Size(393, 852),
          const Size(800, 1333.333333),
          const Size(1333.333333, 800),
          const Size(800, 1333.333333),
          const Size(393, 852),
        ]) {
          resize(tester, size);
          await settle(tester);
          expect(
            camera.events.where((e) => e.startsWith('create:')).length,
            creates,
          );
          expect(camera.events.where((e) => e.startsWith('dispose:')), isEmpty);
          expect(c.tutorialSession, session);
          if (guide != null) {
            expect(tester.state(find.byType(GestureCameraGuide)), same(guide));
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        expect(
          camera.events.where((e) => e.startsWith('dispose:')).length,
          creates,
        );
      },
    );
  }

  testWidgets(
    'landscape setup saves the actual panel ratio and appearance drafts survive rotation',
    (tester) async {
      addTearDown(tester.view.reset);
      resize(tester, const Size(852, 393));
      c.editCamera();
      await tester.pumpWidget(GestureApp(controller: c));
      await settle(tester);
      final area = find.byKey(const ValueKey('camera-position-area'));
      final rect = tester.getRect(area);
      await tester.tapAt(
        Offset(rect.left + rect.width * .3, rect.top + rect.height * .7),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(c.cameraX, closeTo(.3, .001));
      expect(c.cameraY, closeTo(.7, .001));
      c.open(FlowPage.reactions);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('reaction-color-1')));
      await tester.tap(find.byKey(const ValueKey('emoji-1')));
      resize(tester, const Size(393, 852));
      await settle(tester);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(c.faceEmoji, 1);
      expect(c.faceColor, 0xffebf9b1);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets('full-width portrait camera saves actual panel coordinates', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GestureApp(controller: c));
    for (final size in [const Size(393, 852), const Size(800, 1333.333333)]) {
      resize(tester, size);
      c.editCamera();
      await settle(tester);
      final panel = tester.getRect(
        find.byKey(const ValueKey('camera-position-area')),
      );
      await tester.tapAt(
        Offset(panel.left + panel.width * .27, panel.top + panel.height * .71),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(c.cameraX, closeTo(.27, .001));
      expect(c.cameraY, closeTo(.71, .001));
    }
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets(
    'all 21 landscape guides retain the selected hand and locked Next',
    (tester) async {
      addTearDown(tester.view.reset);
      resize(tester, const Size(852, 393));
      await tester.pumpWidget(GestureApp(controller: c));
      for (final group in TutorialGroup.values) {
        for (var i = 0; i < stepsForGroup(group).length; i++) {
          for (final hand in ['Left', 'Right']) {
            await c.setHand(hand);
            c.replayTutorial(i, group: group);
            await settle(tester);
            final guide = tester.widget<GestureCameraGuide>(
              find.byType(GestureCameraGuide),
            );
            expect(guide.isLeftHand, hand == 'Left');
            expect(guide.handPractice, group == TutorialGroup.hand);
            expect(guide.step, stepsForGroup(group)[i]);
            expect(
              tester
                  .widget<FilledButton>(
                    group == TutorialGroup.video
                        ? find.byKey(const ValueKey('social-next'))
                        : find.byType(FilledButton),
                  )
                  .onPressed,
              isNull,
            );
            expect(find.byType(OutlinedButton), findsOneWidget);
            expect(tester.takeException(), isNull, reason: '$group $i $hand');
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets('Bluetooth help and scanning fit short landscape', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    resize(tester, const Size(568, 320));
    c.open(FlowPage.connect);
    await tester.pumpWidget(GestureApp(controller: c));
    for (final issue in BluetoothSetupIssue.values) {
      discovery.issue = issue;
      c.open(FlowPage.connect);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('bluetooth-setup-dialog')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    discovery.issue = null;
    discovery.active = true;
    c.open(FlowPage.connect);
    await settle(tester);
    expect(
      find.byKey(const ValueKey('bluetooth-search-dialog')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual search, Bluetooth dialogs, keyboard forms and logout fit phones and tablets',
    (tester) async {
      addTearDown(tester.view.reset);
      await tester.pumpWidget(GestureApp(controller: c));
      for (final size in [
        const Size(320, 568),
        const Size(568, 320),
        const Size(800, 1333.333333),
        const Size(1333.333333, 800),
      ]) {
        resize(tester, size);
        discovery.issue = null;
        discovery.active = false;
        c.chooseConnection('Manual');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'Manual setup $size');
        discovery.active = true;
        c.chooseConnection('Auto');
        await settle(tester);
        expect(
          find.byKey(const ValueKey('bluetooth-search-dialog')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'Search popup $size');
        discovery.active = false;
        for (final issue in BluetoothSetupIssue.values) {
          discovery.issue = issue;
          c.open(FlowPage.connect);
          await settle(tester);
          expect(
            find.byKey(const ValueKey('bluetooth-setup-dialog')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$issue $size');
          await tester.ensureVisible(
            find.byKey(const ValueKey('bluetooth-setup-primary')),
          );
        }
        discovery.issue = null;
        for (final page in [FlowPage.login, FlowPage.createAccount]) {
          c.open(page);
          await settle(tester);
          final lastField = find.byKey(
            ValueKey(page == FlowPage.login ? 'Password' : 'Confirm Password'),
          );
          await tester.ensureVisible(lastField);
          await tester.showKeyboard(lastField);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await settle(tester);
          await tester.ensureVisible(lastField);
          expect(lastField.hitTestable(), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'Keyboard $page $size',
          );
          tester.view.resetViewInsets();
          tester.testTextInput.hide();
          FocusManager.instance.primaryFocus?.unfocus();
          await settle(tester);
        }
        c.open(FlowPage.settings);
        await settle(tester);
        await tester.tap(find.byTooltip('Log out'));
        await settle(tester);
        expect(find.text('Log out?'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Logout confirmation $size',
        );
        await tester.ensureVisible(find.text('Cancel'));
        await settle(tester);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.text('Log out?'), findsNothing);
        expect(c.page, FlowPage.settings);
      }
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
