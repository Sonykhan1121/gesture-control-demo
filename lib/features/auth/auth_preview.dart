import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';

/// An isolated review prototype. Never calls auth services or writes preferences.
enum AuthPreviewStep {
  registrationCode,
  loginEmail,
  loginCode,
  resetEmail,
  resetPassword,
  linkAccount,
  linkSignIn,
  linkConfirm,
  socialEmail,
  socialCode,
  expired,
  success,
}

class AuthPreviewApp extends StatelessWidget {
  const AuthPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Auth UI preview',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.app,
    home: const AuthPreviewMenu(),
  );
}

class AuthPreviewMenu extends StatelessWidget {
  const AuthPreviewMenu({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('Auth UI preview')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
          children: [
            const LText(
              'Review before integration',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const LText(
              'These are proposed extra screens. Nothing is sent or saved. Use 12345678 for demo codes.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            for (final item in const [
              (
                AuthPreviewStep.registrationCode,
                'Verify signup email',
                'After Create Account → Next',
                Icons.mark_email_read_outlined,
              ),
              (
                AuthPreviewStep.loginEmail,
                'Log in with email code',
                'Optional alternative to password login',
                Icons.password_outlined,
              ),
              (
                AuthPreviewStep.resetEmail,
                'Forgot password',
                'Request code → code and new password',
                Icons.lock_reset_outlined,
              ),
              (
                AuthPreviewStep.linkAccount,
                'Link an existing account',
                'When a social email already has an account',
                Icons.link_outlined,
              ),
              (
                AuthPreviewStep.socialEmail,
                'Verify social email',
                'Only when the provider requires email proof',
                Icons.alternate_email_outlined,
              ),
              (
                AuthPreviewStep.expired,
                'Session expired',
                'Return to login after an expired session',
                Icons.timer_outlined,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  key: ValueKey(item.$1.name),
                  contentPadding: const EdgeInsets.all(16),
                  tileColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(item.$4, color: AppColors.primary),
                  title: LText(
                    item.$2,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LText(
                      item.$3,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AuthPreviewScreen(initialStep: item.$1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class AuthPreviewScreen extends StatefulWidget {
  const AuthPreviewScreen({
    super.key,
    required this.initialStep,
    this.provider = 'Google',
    this.returnSuccess = false,
  });
  final AuthPreviewStep initialStep;
  final String provider;
  final bool returnSuccess;

  @override
  State<AuthPreviewScreen> createState() => _AuthPreviewScreenState();
}

class _AuthPreviewScreenState extends State<AuthPreviewScreen> {
  late AuthPreviewStep step = widget.initialStep;
  final history = <AuthPreviewStep>[];
  final email = TextEditingController(text: 'demo@example.com');
  final code = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  String? error;
  String successTitle = 'You’re ready';
  String successMessage = '';
  bool visible = false;
  int cooldown = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    if (step == AuthPreviewStep.registrationCode) startCooldown();
  }

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    code.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void startCooldown() {
    timer?.cancel();
    cooldown = 60;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => cooldown--);
      if (cooldown == 0) t.cancel();
    });
  }

  void go(AuthPreviewStep next) {
    FocusScope.of(context).unfocus();
    setState(() {
      history.add(step);
      step = next;
      error = null;
      code.clear();
      password.clear();
      confirmation.clear();
      if (next == AuthPreviewStep.loginCode ||
          next == AuthPreviewStep.socialCode ||
          next == AuthPreviewStep.resetPassword) {
        startCooldown();
      }
    });
  }

  void back() {
    if (history.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        step = history.removeLast();
        error = null;
      });
    }
  }

  void finish(String title, String message) {
    successTitle = title;
    successMessage = message;
    go(AuthPreviewStep.success);
  }

  bool validEmail() {
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      return true;
    }
    setState(() => error = 'Enter a valid email address.');
    return false;
  }

  bool validCode() {
    if (code.text == '12345678') return true;
    setState(
      () => error = code.text.length != 8
          ? 'Enter the 8-digit code.'
          : 'That code isn’t correct. Try again.',
    );
    return false;
  }

  void submit() {
    switch (step) {
      case AuthPreviewStep.registrationCode:
        if (validCode()) {
          finish(
            'Email verified',
            'Your account is ready. Log in with your email and password to continue.',
          );
        }
      case AuthPreviewStep.loginEmail:
        if (validEmail()) go(AuthPreviewStep.loginCode);
      case AuthPreviewStep.loginCode:
        if (validCode()) {
          finish(
            'You’re logged in',
            'In the connected app, you’ll continue to your saved setup.',
          );
        }
      case AuthPreviewStep.resetEmail:
        if (validEmail()) go(AuthPreviewStep.resetPassword);
      case AuthPreviewStep.resetPassword:
        if (!validCode()) return;
        if (password.text.length < 8 || password.text.length > 128) {
          setState(() => error = 'Use 8–128 characters for your password.');
          return;
        }
        if (password.text != confirmation.text) {
          setState(() => error = 'Your passwords do not match.');
          return;
        }
        finish(
          'Password reset',
          'Log in with your new password. Your other device sessions will be signed out.',
        );
      case AuthPreviewStep.linkAccount:
        go(AuthPreviewStep.linkSignIn);
      case AuthPreviewStep.linkSignIn:
        if (!validEmail()) return;
        if (password.text.isEmpty) {
          setState(() => error = 'Enter your password.');
          return;
        }
        go(AuthPreviewStep.linkConfirm);
      case AuthPreviewStep.linkConfirm:
        finish(
          '${widget.provider} account linked',
          'You can now use ${widget.provider} or your email and password to log in.',
        );
      case AuthPreviewStep.socialEmail:
        if (validEmail()) go(AuthPreviewStep.socialCode);
      case AuthPreviewStep.socialCode:
        if (validCode()) {
          finish('Email verified', 'Your social login can now continue.');
        }
      case AuthPreviewStep.expired:
        Navigator.of(context).pop();
      case AuthPreviewStep.success:
        Navigator.of(context).pop(widget.returnSuccess ? true : null);
    }
  }

  (String, String, IconData, String) get copy => switch (step) {
    AuthPreviewStep.registrationCode => (
      'Verify your email',
      'Enter the 8-digit code sent to ${email.text.trim()} to create your account.',
      Icons.mark_email_read_outlined,
      'Verify email',
    ),
    AuthPreviewStep.loginEmail => (
      'Log in with a code',
      'Enter your registered email. We’ll send a code so you can log in without your password.',
      Icons.password_outlined,
      'Send code',
    ),
    AuthPreviewStep.loginCode => (
      'Check your email',
      'Enter the 8-digit login code sent to ${email.text.trim()}.',
      Icons.mark_email_read_outlined,
      'Log In',
    ),
    AuthPreviewStep.resetEmail => (
      'Forgot password?',
      'Enter your account email to receive a password reset code.',
      Icons.lock_reset_outlined,
      'Send reset code',
    ),
    AuthPreviewStep.resetPassword => (
      'Reset your password',
      'If ${email.text.trim()} is eligible, a code has been sent. Enter it below and choose a new password.',
      Icons.lock_reset_outlined,
      'Reset password',
    ),
    AuthPreviewStep.linkAccount => (
      'You already have an account',
      'An account already uses this email. Log in to that account first, then choose whether to link ${widget.provider}.',
      Icons.link_outlined,
      'Log in to existing account',
    ),
    AuthPreviewStep.linkSignIn => (
      'Log in to link ${widget.provider}',
      'Use your existing account password. ${widget.provider} will only be linked after your confirmation.',
      Icons.lock_outline,
      'Continue',
    ),
    AuthPreviewStep.linkConfirm => (
      'Link ${widget.provider}?',
      'Allow your ${widget.provider} account to log in to your existing account at ${email.text.trim()}?',
      Icons.link_outlined,
      'Link ${widget.provider} account',
    ),
    AuthPreviewStep.socialEmail => (
      'Verify your email',
      'Your sign-in provider needs email verification. Confirm your email to continue.',
      Icons.alternate_email_outlined,
      'Send code',
    ),
    AuthPreviewStep.socialCode => (
      'Check your email',
      'Enter the 8-digit verification code sent to ${email.text.trim()}.',
      Icons.mark_email_read_outlined,
      'Verify and continue',
    ),
    AuthPreviewStep.expired => (
      'Please log in again',
      'Your session has expired. Log in again to continue with your account. Your saved device setup stays on this phone.',
      Icons.timer_outlined,
      'Back to Log In',
    ),
    AuthPreviewStep.success => (
      successTitle,
      successMessage,
      Icons.check_rounded,
      successTitle == 'Email verified' &&
                  widget.initialStep == AuthPreviewStep.registrationCode ||
              successTitle == 'Password reset'
          ? 'Back to Log In'
          : 'Done',
    ),
  };

  Widget input(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey(label),
      controller: controller,
      obscureText: secret && !visible,
      keyboardType: secret
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      autofillHints: null,
      autocorrect: false,
      enableSuggestions: !secret,
      inputFormatters: secret ? [LengthLimitingTextInputFormatter(128)] : null,
      decoration: InputDecoration(
        labelText: tr(context, label),
        suffixIcon: secret
            ? IconButton(
                tooltip: tr(
                  context,
                  visible ? 'Hide password' : 'Show password',
                ),
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
      ),
    ),
  );

  Widget otp() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LText(
        'Verification code',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, bounds) => TextField(
          key: const ValueKey('Verification code'),
          controller: code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autocorrect: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: bounds.maxWidth < 330 ? 8 : 12,
          ),
          decoration: InputDecoration(
            hintText: '00000000',
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 18,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const LText(
        'Code expires in 5 minutes',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: cooldown > 0
              ? null
              : () {
                  setState(startCooldown);
                  AppToast.show(context, 'Demo: a new code would be sent.');
                },
          child: LText(
            cooldown > 0 ? 'Resend code in ${cooldown}s' : 'Resend code',
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final (title, description, icon, action) = copy;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ([
          AuthPreviewStep.loginEmail,
          AuthPreviewStep.resetEmail,
          AuthPreviewStep.linkSignIn,
          AuthPreviewStep.socialEmail,
        ].contains(step))
          input('Email', email),
        if ([
          AuthPreviewStep.registrationCode,
          AuthPreviewStep.loginCode,
          AuthPreviewStep.socialCode,
          AuthPreviewStep.resetPassword,
        ].contains(step))
          otp(),
        if (step == AuthPreviewStep.linkSignIn)
          input('Password', password, secret: true),
        if (step == AuthPreviewStep.resetPassword) ...[
          const SizedBox(height: 12),
          input('New password', password, secret: true),
          input('Confirm password', confirmation, secret: true),
          const LText(
            'Use 8–128 characters.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
        ],
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: LText(
              error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 48,
          child: FilledButton(
            key: const ValueKey('auth-preview-primary'),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: submit,
            child: LText(
              action,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (step == AuthPreviewStep.linkConfirm)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LText('Not now'),
          ),
        if (step == AuthPreviewStep.loginEmail)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const LText('Use password instead'),
          ),
      ],
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 34),
        ),
        const SizedBox(height: 26),
        LText(
          title,
          style: const TextStyle(
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        LText(
          description,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
    return PopScope(
      canPop: history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: tr(context, 'Back'),
              onPressed: back,
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 22),
                child: Center(
                  child: LText(
                    'UI DEMO',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xff20251b),
                  AppColors.background,
                  AppColors.background,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final wide = bounds.maxWidth > bounds.maxHeight;
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      wide ? 36 : 24,
                      wide ? 20 : 48,
                      wide ? 36 : 24,
                      24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: wide ? 900 : 400),
                        child: Column(
                          children: [
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: intro),
                                  const SizedBox(width: 48),
                                  Expanded(child: form),
                                ],
                              )
                            else ...[
                              intro,
                              const SizedBox(height: 36),
                              form,
                            ],
                            const SizedBox(height: 32),
                            const LText(
                              'Preview only · No email sent or account changed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.subtleText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
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
