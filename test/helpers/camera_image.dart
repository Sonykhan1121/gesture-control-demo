import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;

/// Synthetic padded camera bytes only; never a person's captured measurements.
CameraImage syntheticCameraImage({bool ios = false}) =>
    CameraImage.fromPlatformInterface(
      platform.CameraImageData(
        format: platform.CameraImageFormat(
          ios ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
          raw: ios ? 1111970369 : 35,
        ),
        width: 4,
        height: 2,
        planes: [
          platform.CameraImagePlane(
            bytes: Uint8List(ios ? 48 : 16),
            bytesPerRow: ios ? 24 : 8,
            bytesPerPixel: ios ? 4 : 1,
          ),
          if (!ios)
            for (var i = 0; i < 2; i++)
              platform.CameraImagePlane(
                bytes: Uint8List(8),
                bytesPerRow: 8,
                bytesPerPixel: 2,
              ),
        ],
      ),
    );
