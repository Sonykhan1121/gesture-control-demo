import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../l10n/app_strings.dart';

/// Persistent correction below the demo hand, independent of guide opacity.
class TutorialHandHint extends StatelessWidget {
  const TutorialHandHint({required this.hand, this.textKey, super.key});

  final String hand;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.noticeSurface,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
      ),
      child: Text(
        tr(context, 'Please use your $hand hand'),
        key: textKey,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
