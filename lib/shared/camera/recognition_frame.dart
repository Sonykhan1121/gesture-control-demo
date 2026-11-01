import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One channel contract for hand and face inference on both mobile hosts.
/// AVFoundation streams are already upright and front-camera mirrored. Android
/// YUV buffers still need sensor/device rotation and a front-camera reflection.
Map<String, Object> recognitionFrame(
  CameraImage image,
  CameraDescription camera,
  DeviceOrientation orientation,
) {
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  final deviceRotation = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final front = camera.lensDirection == CameraLensDirection.front;
  return {
    'width': image.width,
    'height': image.height,
    'format': image.format.group == ImageFormatGroup.bgra8888
        ? 'bgra8888'
        : 'yuv420',
    'alreadyUpright': ios,
    'rotation': ios
        ? 0
        : front
        ? (camera.sensorOrientation + deviceRotation) % 360
        : (camera.sensorOrientation - deviceRotation + 360) % 360,
    'mirror': front,
    'planes': image.planes
        .map(
          (plane) => {
            'bytes': plane.bytes,
            'rowStride': plane.bytesPerRow,
            'pixelStride': plane.bytesPerPixel ?? 1,
          },
        )
        .toList(),
  };
}
