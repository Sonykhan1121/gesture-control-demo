import 'package:hand_gesture/shared/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/l10n/app_language.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});
  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguage>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const LText('Language')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RadioGroup<String>(
              groupValue: language.code,
              onChanged: (value) async {
                if (value == null || _saving) return;
                setState(() => _saving = true);
                try {
                  await language.select(value);
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Unable to save language. Please try again.',
                    );
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                itemCount: AppStrings.names.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final item = AppStrings.names.entries.elementAt(index);
                  return Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    child: RadioListTile<String>(
                      key: ValueKey('language-${item.key}'),
                      value: item.key,
                      enabled: !_saving,
                      title: Text(item.value, locale: Locale(item.key)),
                      activeColor: AppColors.primary,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
