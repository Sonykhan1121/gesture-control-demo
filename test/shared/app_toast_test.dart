import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/shared/app_toast.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(1333, 800)]) {
    testWidgets('designed toast replaces old messages and fits $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                page = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      AppToast.show(page, 'Old message');
      await tester.pumpAndSettle();
      AppToast.show(
        page,
        'Your verification code was requested. Please check your email and return to continue.',
      );
      await tester.pumpAndSettle();
      expect(find.text('Old message'), findsNothing);
      final card = find.byType(AppToastCard);
      expect(card, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(of: card, matching: find.byType(Container)),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.noticeSurface);
      expect((decoration.border as Border).top.color, AppColors.primary);
      final text = tester.widget<Text>(
        find.descendant(of: card, matching: find.byType(Text)),
      );
      expect(text.style!.color, AppColors.primary);
      final bounds = tester.getRect(card);
      expect(bounds.center.dx, closeTo(size.width / 2, .01));
      expect(bounds.left, greaterThanOrEqualTo(24));
      expect(bounds.right, lessThanOrEqualTo(size.width - 24));
      expect(bounds.bottom, lessThanOrEqualTo(size.height - 24));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(card, findsNothing);
    });
  }
}
