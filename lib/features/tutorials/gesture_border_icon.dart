import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws only the silhouette border of an opaque hand illustration.
/// The source RGB (skin, nails and finger creases) never appears in the badge.
class GestureBorderIcon extends StatefulWidget {
  const GestureBorderIcon({
    required this.assetPath,
    required this.color,
    this.size = 44,
    super.key,
  });

  final String assetPath;
  final Color color;
  final double size;

  @override
  State<GestureBorderIcon> createState() => _GestureBorderIconState();
}

class _GestureBorderIconState extends State<GestureBorderIcon> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener(_onImage);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(GestureBorderIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) _resolve();
  }

  void _resolve() {
    final stream = AssetImage(
      widget.assetPath,
    ).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _replaceImage(null);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    setState(() => _replaceImage(info));
  }

  void _replaceImage(ImageInfo? info) {
    final previous = _info;
    _info = info;
    // A painter from this frame can still reference the previous image.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _replaceImage(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(widget.size),
    painter: _GestureBorderPainter(_info?.image, widget.color),
  );
}

class _GestureBorderPainter extends CustomPainter {
  const _GestureBorderPainter(this.image, this.color);

  final ui.Image? image;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final hand = image;
    if (hand == null) return;
    final sourceSize = Size(hand.width.toDouble(), hand.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final source = Offset.zero & sourceSize;
    // Expand the silhouette, then cut its centre out on an isolated layer.
    // dstOut uses alpha only, so interior illustration details cannot become
    // lines. The hollow centre preserves the actual card background underneath.
    canvas.saveLayer((Offset.zero & size).inflate(2), Paint());
    canvas.drawImageRect(
      hand,
      source,
      destination,
      Paint()
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
        ..imageFilter = ui.ImageFilter.dilate(radiusX: 1, radiusY: 1)
        ..filterQuality = FilterQuality.high,
    );
    canvas.drawImageRect(
      hand,
      source,
      destination,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..imageFilter = ui.ImageFilter.erode(radiusX: 1, radiusY: 1)
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GestureBorderPainter oldDelegate) =>
      image != oldDelegate.image || color != oldDelegate.color;
}
