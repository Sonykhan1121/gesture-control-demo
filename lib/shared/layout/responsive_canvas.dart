import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Phones retain their approved canvas sizes. Larger displays scale the same
/// typography, controls and artwork together, using both available dimensions.
bool expandedCanvas(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

double portraitCanvasWidth(BuildContext context, BoxConstraints viewport) {
  return viewport.maxWidth;
}

double portraitCanvasScale(BuildContext context, BoxConstraints viewport) {
  if (!expandedCanvas(context)) return viewport.maxWidth / 402;
  // Opening the keyboard must scroll the form, not shrink its text/buttons.
  final fullHeight =
      viewport.maxHeight + MediaQuery.viewInsetsOf(context).bottom;
  final scale = math.min(viewport.maxWidth / 402, fullHeight / 874);
  return scale;
}

/// The original portrait reference places its header at y=62, including a
/// simulated status-bar allowance. Use the real inset once, in screen pixels,
/// so scaling a tablet canvas cannot enlarge the blank space above the header.
double portraitHeaderOffset(BuildContext context, double scale) =>
    (MediaQuery.paddingOf(context).top + 8) / scale - 62;

/// Reflow horizontal design positions across the full canvas. Children receive
/// the wider constraints, so fields/buttons grow without stretching glyphs,
/// hand artwork, circular icons or border radii.
List<Widget> portraitCanvasChildren(
  List<Widget> children,
  double width, {
  double topOffset = 0,
}) {
  final factor = width / 402;
  if ((factor - 1).abs() < .000001 && topOffset == 0) return children;
  double? x(double? value) => value == null ? null : value * factor;
  return children.map((child) {
    if (child is! Positioned) return child;
    return Positioned(
      key: child.key,
      left: x(child.left),
      right: x(child.right),
      width: x(child.width),
      top: child.top == null ? null : child.top! + topOffset,
      bottom: child.bottom,
      height: child.height,
      child: child.child,
    );
  }).toList();
}

/// Scale an approved landscape composition on tablets without applying a
/// second font multiplier to its already-scaled design coordinates.
class ResponsiveLandscape extends StatelessWidget {
  const ResponsiveLandscape({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (!expandedCanvas(context)) return builder(context);
    return LayoutBuilder(
      builder: (context, viewport) {
        final media = MediaQuery.of(context);
        final scale = math.min(
          viewport.maxWidth / 874,
          (viewport.maxHeight + media.viewInsets.bottom) / 402,
        );
        final size = Size(
          viewport.maxWidth / scale,
          viewport.maxHeight / scale,
        );
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: media.copyWith(
                  size: size,
                  padding: media.padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                ),
                child: Builder(builder: builder),
              ),
            ),
          ),
        );
      },
    );
  }
}
