import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/shared/camera/recognition_frame.dart';
import '../../helpers/camera_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Android keeps sensor rotation, mirroring and padded YUV plane strides',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final front in [true, false]) {
        final camera = CameraDescription(
          name: 'camera',
          lensDirection: front
              ? CameraLensDirection.front
              : CameraLensDirection.back,
          sensorOrientation: front ? 270 : 90,
        );
        for (var i = 0; i < DeviceOrientation.values.length; i++) {
          final frame = recognitionFrame(
            syntheticCameraImage(),
            camera,
            DeviceOrientation.values[i],
          );
          final degrees = [0, 90, 180, 270][i];
          expect(
            frame['rotation'],
            front ? (270 + degrees) % 360 : (90 - degrees + 360) % 360,
          );
          expect(frame['alreadyUpright'], false);
          expect(frame['mirror'], front);
          expect(frame['format'], 'yuv420');
          final planes = frame['planes'] as List;
          expect(planes.length, 3);
          expect(planes[0]['rowStride'], 8);
          expect(planes[1]['pixelStride'], 2);
        }
      }
    },
  );

  test(
    'iOS never rotates or reflects the already oriented BGRA stream again',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final front in [true, false]) {
        for (final orientation in DeviceOrientation.values) {
          final frame = recognitionFrame(
            syntheticCameraImage(ios: true),
            CameraDescription(
              name: 'camera',
              lensDirection: front
                  ? CameraLensDirection.front
                  : CameraLensDirection.back,
              sensorOrientation: 90,
            ),
            orientation,
          );
          expect(frame['rotation'], 0);
          expect(frame['alreadyUpright'], true);
          expect(frame['mirror'], front);
          expect(frame['format'], 'bgra8888');
          final planes = frame['planes'] as List;
          expect(planes.length, 1);
          expect(planes[0]['rowStride'], 24);
          expect((planes[0]['bytes'] as List).length, 48);
        }
      }
    },
  );

  test(
    'Both clients send the same iOS frame schema and preserve image-space hand identity',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map? handFrame, faceFrame;
      messenger.setMockMethodCallHandler(HandRecognition.channel, (call) async {
        handFrame = call.arguments as Map;
        return {'width': 4, 'height': 2, 'hand': 'Left', 'mirrored': true};
      });
      messenger.setMockMethodCallHandler(FaceTracking.channel, (call) async {
        faceFrame = call.arguments as Map;
        return {'detected': false};
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(HandRecognition.channel, null);
        messenger.setMockMethodCallHandler(FaceTracking.channel, null);
      });
      const camera = CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 90,
      );
      final image = syntheticCameraImage(ios: true);
      final observation = await HandRecognition().recognize(
        image,
        camera,
        DeviceOrientation.landscapeRight,
      );
      expect(
        await FaceTracking().recognize(
          image,
          camera,
          DeviceOrientation.landscapeRight,
        ),
        isNull,
      );
      expect(faceFrame, equals(handFrame));
      expect(observation.hand, 'Left');
      expect(observation.physicalHand, 'Right');
    },
  );
}
