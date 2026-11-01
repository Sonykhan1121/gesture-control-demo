import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/auth/auth_flow_layout.dart';

void main() {
  testWidgets('tablet forms fill both orientations and keep keyboard sizing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    for (final size in [const Size(800, 1280), const Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthFlowLayout(
              intro: const Text('Reset your password'),
              form: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TextField(),
                  SizedBox(
                    key: const ValueKey('action'),
                    height: 48,
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Size visualSize() {
        final box = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('action')),
        );
        final delta =
            box.localToGlobal(box.size.bottomRight(Offset.zero)) -
            box.localToGlobal(Offset.zero);
        return Size(delta.dx, delta.dy);
      }

      final before = visualSize();
      expect(before.width, greaterThan(size.width < size.height ? 650 : 450));
      expect(before.height, greaterThan(70));
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();
      expect(visualSize(), before);
      expect(tester.takeException(), isNull);
    }
  });
}
