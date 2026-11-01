import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleOutline(WidgetTester tester, String path) async {
  final present = File(path).existsSync();
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    if (present && find.byKey(ValueKey('guide-$path')).evaluate().isNotEmpty) {
      return;
    }
    if (!present &&
        find
            .textContaining('Outline or size reference missing:')
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  fail('Outline did not settle: $path');
}
