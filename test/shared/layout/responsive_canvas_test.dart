import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/shared/layout/responsive_canvas.dart';

void main() {
  Widget host(Size size, WidgetBuilder builder, {double keyboard = 0}) =>
      MediaQuery(
        data: MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: builder),
        ),
      );

  testWidgets(
    'phone widths stay unchanged; Lenovo canvas fills the height without clipping',
    (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(393, 852),
        const Size(800, 1333.333333),
      ]) {
        double width = 0, scale = 0;
        await tester.pumpWidget(
          host(size, (context) {
            width = portraitCanvasWidth(context, BoxConstraints.tight(size));
            scale = portraitCanvasScale(context, BoxConstraints.tight(size));
            return const SizedBox();
          }),
        );
        if (size.width < 600) {
          expect(width, size.width);
        } else {
          expect(
            width,
            greaterThan(600),
            reason: 'Do not retain the old 402px strip',
          );
          expect(width, size.width, reason: 'Use the entire screen width');
          expect(874 * scale, closeTo(size.height, .0001));
          final positioned =
              portraitCanvasChildren([
                    const Positioned(
                      left: 20,
                      top: 807,
                      width: 362,
                      height: 44,
                      child: SizedBox(),
                    ),
                  ], width / scale).single
                  as Positioned;
          expect(
            positioned.width! * scale,
            closeTo(size.width * 362 / 402, .0001),
          );
          expect(
            positioned.height,
            44,
            reason: 'Wider controls must not stretch their text vertically',
          );
        }
      }
    },
  );

  testWidgets('keyboard does not shrink tablet fonts or controls', (
    tester,
  ) async {
    final widths = <double>[];
    const size = Size(800, 1333.333333);
    for (final keyboard in [0.0, 360.0]) {
      await tester.pumpWidget(
        host(size, (context) {
          widths.add(
            portraitCanvasScale(
              context,
              BoxConstraints.tight(Size(size.width, size.height - keyboard)),
            ),
          );
          return const SizedBox();
        }, keyboard: keyboard),
      );
    }
    expect(widths[0], widths[1]);
  });

  testWidgets('tablet landscape scales type and corrects safe areas once', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1333, 800);
    addTearDown(tester.view.reset);
    late MediaQueryData local;
    final marker = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1333, 800),
          padding: EdgeInsets.only(top: 24, bottom: 24),
          viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ResponsiveLandscape(
            builder: (context) {
              local = MediaQuery.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(key: marker, width: 44, height: 44),
              );
            },
          ),
        ),
      ),
    );
    final scale = 1333 / 874;
    expect(local.size.width, closeTo(874, .0001));
    expect(local.padding.top * scale, closeTo(24, .0001));
    final rect = tester.getRect(find.byKey(marker));
    expect(rect.width, closeTo(44 * scale, .0001));
    expect(rect.height, closeTo(44 * scale, .0001));
  });
}
