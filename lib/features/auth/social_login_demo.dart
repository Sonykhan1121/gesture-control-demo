import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'auth_preview.dart';

enum SocialDemoResult { existing, newAccount, failed }

/// Simulates the external provider and callback without opening a browser,
/// transmitting account information, or acquiring an OAuth credential.
class SocialLoginDemo extends StatefulWidget {
  const SocialLoginDemo({super.key, required this.provider});
  final String provider;

  @override
  State<SocialLoginDemo> createState() => _SocialLoginDemoState();
}

class _SocialLoginDemoState extends State<SocialLoginDemo> {
  bool busy = false;

  Future<void> complete(SocialDemoResult result) async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> branch(AuthPreviewStep step) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuthPreviewScreen(
          initialStep: step,
          provider: widget.provider,
          returnSuccess: true,
        ),
      ),
    );
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context).pop(SocialDemoResult.existing);
    } else {
      // Cancelling linking/verification returns to the original login screen.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: LText('${widget.provider} sign-in'),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 18),
          child: Center(
            child: LText(
              'UI DEMO',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/auth/${widget.provider.toLowerCase()}.png',
                    width: 52,
                    height: 52,
                  ),
                ),
                const SizedBox(height: 24),
                const LText(
                  'Choose an account',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                LText(
                  'to continue to lazivoo with ${widget.provider}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const LText(
                    'Simulated provider screen. The connected version will open the secure Google or Facebook page. No real account is accessed here.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  account(
                    'Demo user',
                    'demo@example.com',
                    'Existing linked account',
                    SocialDemoResult.existing,
                  ),
                  const SizedBox(height: 12),
                  account(
                    'New user',
                    'new@example.com',
                    'First-time signup',
                    SocialDemoResult.newAccount,
                  ),
                  const SizedBox(height: 20),
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const LText(
                        'Preview other outcomes',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      children: [
                        scenario(
                          'Email already has an account',
                          () => branch(AuthPreviewStep.linkAccount),
                        ),
                        scenario(
                          'Email verification required',
                          () => branch(AuthPreviewStep.socialEmail),
                        ),
                        scenario(
                          'Sign-in failed',
                          () => Navigator.of(
                            context,
                          ).pop(SocialDemoResult.failed),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const LText('Cancel'),
                  ),
                ],
                const SizedBox(height: 16),
                const LText(
                  'Demo only · No API connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.subtleText, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget account(
    String name,
    String email,
    String detail,
    SocialDemoResult result,
  ) => OutlinedButton(
    key: ValueKey('social-${result.name}'),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.all(16),
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.centerLeft,
    ),
    onPressed: () => complete(result),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          child: LText(name[0]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              LText(
                email,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              LText(
                detail,
                style: const TextStyle(color: AppColors.primary, fontSize: 11),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ),
  );

  Widget scenario(String title, VoidCallback action) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: LText(title, style: const TextStyle(fontSize: 13)),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: action,
  );
}
