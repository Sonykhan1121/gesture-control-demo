import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';

import 'gesture_diagnostics.dart';

/// Visible diagnostics for a tester; collapsing this never changes detection.
class GestureDebugOverlay extends StatefulWidget {
  const GestureDebugOverlay({
    super.key,
    required this.target,
    required this.status,
    required this.checks,
    required this.hold,
    required this.matching,
    required this.complete,
    this.nativeReading,
    this.components = const {},
  });

  final String target, status, hold;
  final List<GestureCheck> checks;
  final bool matching, complete;
  final String? nativeReading;
  final Map<String, double> components;

  @override
  State<GestureDebugOverlay> createState() => _GestureDebugOverlayState();
}

class _GestureDebugOverlayState extends State<GestureDebugOverlay> {
  bool _expanded = true;
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final good = widget.matching || widget.complete;
    return Material(
      color: const Color(0xEE101419),
      borderRadius: BorderRadius.circular(8),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: AppTypography.bodyFont,
          color: Colors.white,
          fontSize: 11,
          height: 1.3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('gesture-debug-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Semantics(
                button: true,
                label: _expanded
                    ? 'Collapse gesture debug'
                    : 'Expand gesture debug',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bug_report_outlined,
                        size: 16,
                        color: good ? AppColors.primary : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: LText(
                          'Debug · ${widget.target}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      LText(
                        widget.hold,
                        key: const ValueKey('gesture-debug-hold'),
                        style: TextStyle(
                          color: good ? AppColors.primary : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: LText(
                widget.status,
                key: const ValueKey('gesture-debug-status'),
                style: TextStyle(
                  color: good ? AppColors.primary : const Color(0xFFFFC66D),
                ),
              ),
            ),
            if (_expanded)
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('gesture-debug-readings'),
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final check in widget.checks) _check(check),
                      if (widget.nativeReading != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: LText(
                            widget.nativeReading!,
                            key: const ValueKey('gesture-debug-native'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      InkWell(
                        key: const ValueKey('gesture-debug-details'),
                        onTap: () => setState(() => _details = !_details),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: LText(
                            _details
                                ? 'Hide score details ▴'
                                : 'Score details ▾',
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ),
                      if (_details) ...[
                        const LText(
                          'Pose score = model confidence or shape fit, not accuracy. '
                          'Shape readings below are informational: an alternative model or Punch fit can pass.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        for (final component in widget.components.entries)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: LText(
                              '${_label(component.key)}: ${gesturePercent(component.value)}',
                            ),
                          ),
                        if (widget.components.isEmpty)
                          const LText('No shape readings for this frame.'),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _check(GestureCheck check) {
    final color = switch (check.passed) {
      true => AppColors.primary,
      false => const Color(0xFFFF9999),
      null => Colors.white60,
    };
    return Padding(
      key: ValueKey('gesture-debug-${check.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: LText(
              switch (check.passed) {
                true => 'PASS',
                false => 'FAIL',
                null => 'WAIT',
              },
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: LText('${check.label}: ${check.detail}')),
        ],
      ),
    );
  }

  String _label(String name) {
    final words = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]!.toLowerCase()}',
    );
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }
}
