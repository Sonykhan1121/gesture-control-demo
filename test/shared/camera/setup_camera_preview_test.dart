import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

// Exercise real CameraController creation/disposal against a fake native camera.
// In the pinned camera plugin, disposing a controller does NOT stop its stream.
class FakeCameraPlatform extends CameraPlatform {
  Size previewSize = const Size(320, 240);
  final events = <String>[];
  final frames = <int, StreamController<CameraImageData>>{};
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final orientation =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  int nextId = 0;
  Completer<void>? initializationGate;
  Completer<void>? creationGate;
  bool denyCreateOnce = false;
  Completer<void>? cancellationGate;
  bool failDisposeOnce = false;
  bool failStopOnce = false;
  bool failInitializeOnce = false;
  ImageFormatGroup? initializedFormat;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  ];

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    final id = ++nextId;
    events.add('create:$id');
    await creationGate?.future;
    if (denyCreateOnce) {
      denyCreateOnce = false;
      throw CameraException('CameraAccessDenied', 'Camera permission denied');
    }
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initializedFormat = imageFormatGroup;
    await initializationGate?.future;
    if (failInitializeOnce) {
      failInitializeOnce = false;
      throw CameraException('testInitialize', 'Camera temporarily unavailable');
    }
    initialized.add(
      CameraInitializedEvent(
        cameraId,
        previewSize.width,
        previewSize.height,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientation.stream;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    final stream = StreamController<CameraImageData>(
      onListen: () => events.add('start:$cameraId'),
      onCancel: () async {
        events.add('stop:$cameraId');
        await cancellationGate?.future;
        if (failStopOnce) {
          failStopOnce = false;
          throw CameraException('testStop', 'Already closed by OS');
        }
        events.add('stopped:$cameraId');
      },
    );
    frames[cameraId] = stream;
    return stream.stream;
  }

  @override
  Future<void> dispose(int cameraId) async {
    events.add('dispose:$cameraId');
    if (failDisposeOnce) {
      failDisposeOnce = false;
      throw CameraException('testDispose', 'Already closed by OS');
    }
  }

  void emit(int id) => frames[id]!.add(
    const CameraImageData(
      format: CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      planes: [],
      width: 320,
      height: 240,
    ),
  );

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();
}

void main() {
  late CameraPlatform original;
  late FakeCameraPlatform camera;
  setUp(() {
    original = CameraPlatform.instance;
    camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });
  tearDown(() => CameraPlatform.instance = original);

  Widget preview(
    String route, {
    void Function()? onFrame,
    bool hidden = false,
  }) => MaterialApp(
    home: SetupCameraPreview(
      key: ValueKey(route),
      showPreview: !hidden,
      onFrame: onFrame == null ? null : (_, _, _) => onFrame(),
    ),
  );

  testWidgets('iOS requests BGRA while Android retains YUV camera frames', (
    tester,
  ) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(preview(platform.name, onFrame: () {}));
      await tester.pumpAndSettle();
      expect(
        camera.initializedFormat,
        platform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Back/Skip and re-entry cancel the old stream before new frames',
    (tester) async {
      var oldFrames = 0;
      var newFrames = 0;
      await tester.pumpWidget(preview('hand', onFrame: () => oldFrames++));
      await tester.pumpAndSettle();
      camera.emit(1);
      await tester.pump();
      expect(oldFrames, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(camera.frames[1]!.hasListener, isFalse);
      await tester.pumpWidget(
        preview('hand-again', onFrame: () => newFrames++),
      );
      await tester.pumpAndSettle();
      camera.emit(2);
      await tester.pump();
      expect(newFrames, 1);
      expect(camera.events, [
        'create:1',
        'start:1',
        'stop:1',
        'stopped:1',
        'dispose:1',
        'create:2',
        'start:2',
      ]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('face to tutorial handoff waits for image-stream cancellation', (
    tester,
  ) async {
    await tester.pumpWidget(preview('face', hidden: true, onFrame: () {}));
    await tester.pumpAndSettle();
    camera.cancellationGate = Completer<void>();
    await tester.pumpWidget(preview('tutorial', onFrame: () {}));
    await tester.pump();
    expect(camera.nextId, 1, reason: 'Do not start over a closing stream');
    camera.cancellationGate!.complete();
    await tester.pumpAndSettle();
    expect(
      camera.events.indexOf('stopped:1'),
      lessThan(camera.events.indexOf('create:2')),
    );
    expect(camera.frames[1]!.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('rapid background/resume replaces the interrupted camera', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(preview('hand', onFrame: () {}));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.nextId, 2);
    expect(camera.frames[1]!.hasListener, isFalse);
    expect(camera.frames[2]!.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('leaving during initialization never starts an obsolete stream', (
    tester,
  ) async {
    camera.initializationGate = Completer<void>();
    await tester.pumpWidget(preview('hand', onFrame: () {}));
    await tester.pump();
    await tester.pumpWidget(preview('video', onFrame: () {}));
    camera.initializationGate!.complete();
    await tester.pumpAndSettle();
    expect(camera.events, ['create:1', 'dispose:1', 'create:2', 'start:2']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'preview-only camera starts detection when a frame callback is added',
    (tester) async {
      await tester.pumpWidget(preview('setup'));
      await tester.pumpAndSettle();
      expect(camera.frames, isEmpty);
      var received = 0;
      await tester.pumpWidget(preview('setup', onFrame: () => received++));
      await tester.pumpAndSettle();
      camera.emit(2);
      await tester.pump();
      expect(received, 1);
      await tester.pumpWidget(preview('setup'));
      await tester.pumpAndSettle();
      expect(camera.frames[2]!.hasListener, isFalse);
      expect(camera.nextId, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed initialization disposes its candidate and Retry recovers',
    (tester) async {
      camera.failInitializeOnce = true;
      await tester.pumpWidget(preview('hand', onFrame: () {}));
      await tester.pumpAndSettle();
      expect(camera.events, ['create:1', 'dispose:1']);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(camera.frames[2]!.hasListener, isTrue);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final deniedBeforeResume in [true, false]) {
    testWidgets(
      'permission denial survives lifecycle churn (before resume: $deniedBeforeResume)',
      (tester) async {
        const channel = MethodChannel(
          'flutter.baseflow.com/permissions/methods',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => 0,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        camera.creationGate = Completer<void>();
        camera.denyCreateOnce = true;
        await tester.pumpWidget(preview('permission', onFrame: () {}));
        await tester.pump();
        expect(camera.nextId, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (deniedBeforeResume) {
          camera.creationGate!.complete();
          await tester.pumpAndSettle();
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        if (!deniedBeforeResume) camera.creationGate!.complete();
        await tester.pumpAndSettle();
        expect(
          camera.nextId,
          1,
          reason: 'Deny must not silently request camera again',
        );
        expect(
          find.text('Allow camera access in phone Settings, then return.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Open Settings'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(camera.frames[2]!.hasListener, isTrue);
        expect(find.text('Retry'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'settings grant recovers denied camera; returning without grant does not reprompt',
    (tester) async {
      const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
      var granted = false;
      var settingsOpened = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'openAppSettings') {
          settingsOpened++;
          return true;
        }
        return granted ? 1 : 0;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      camera.denyCreateOnce = true;
      await tester.pumpWidget(preview('permission-settings', onFrame: () {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(settingsOpened, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.nextId, 1);
      expect(find.text('Retry'), findsOneWidget);
      granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.frames[2]!.hasListener, isTrue);
      expect(find.text('Open Settings'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final failure in ['stop', 'dispose']) {
    testWidgets(
      '$failure failure still releases resources and allows reopening',
      (tester) async {
        await tester.pumpWidget(preview('hand', onFrame: () {}));
        await tester.pumpAndSettle();
        camera.failStopOnce = failure == 'stop';
        camera.failDisposeOnce = failure == 'dispose';
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(preview('hand-again', onFrame: () {}));
        await tester.pumpAndSettle();
        expect(camera.nextId, 2);
        expect(camera.events, contains('dispose:1'));
        expect(camera.frames[2]!.hasListener, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
