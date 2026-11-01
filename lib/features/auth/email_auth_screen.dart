import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:async';

import 'auth_flow_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'services/auth_api.dart';
import 'services/demo_auth.dart';
import 'services/auth_service.dart';
import 'services/auth_session.dart';

enum EmailAuthPurpose { registration, login, reset }

class EmailAuthResult {
  const EmailAuthResult(this.email, {this.session, this.message});
  final String email;
  final AuthSession? session;
  final String? message;
}

/// Real email flows matching the approved review screens. Secrets stay in memory.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({
    super.key,
    required this.auth,
    required this.purpose,
    this.email = '',
    this.name = '',
    this.password = '',
    this.temporaryLogin = false,
  });
  final AuthService auth;
  final EmailAuthPurpose purpose;
  final String email, name, password;
  final bool temporaryLogin;
  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  late final email = TextEditingController(text: widget.email);
  final code = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool sent = false, busy = false, visible = false;
  bool registrationVerified = false;
  String? error, success;
  int cooldown = 0;
  DateTime? resendAt;
  Timer? timer;
  bool get registration => widget.purpose == EmailAuthPurpose.registration;
  bool get reset => widget.purpose == EmailAuthPurpose.reset;
  String get address => email.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    if (registration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(send());
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    email.dispose();
    code.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  void countdown([int seconds = 60]) {
    timer?.cancel();
    resendAt = DateTime.now().add(Duration(seconds: seconds.clamp(1, 3600)));
    cooldown = seconds.clamp(1, 3600);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(
        () => cooldown =
            (resendAt!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, 3600),
      );
      if (cooldown == 0) t.cancel();
    });
  }

  Future<void> send() async {
    if (busy || cooldown > 0 || registrationVerified) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address) ||
        address.length > 254) {
      setState(() => error = 'Enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      switch (widget.purpose) {
        case EmailAuthPurpose.registration:
          await widget.auth.requestRegistration(
            widget.name,
            address,
            widget.password,
          );
        case EmailAuthPurpose.login:
          await widget.auth.requestLoginCode(address);
        case EmailAuthPurpose.reset:
          await widget.auth.requestPasswordReset(address);
      }
      if (mounted) {
        setState(() {
          sent = true;
          code.clear();
          countdown();
        });
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.message;
          if (failure.retryAfter != null) countdown(failure.retryAfter!);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    if (success != null) {
      Navigator.of(context).pop(EmailAuthResult(address, message: success));
      return;
    }
    if (!sent) {
      await send();
      return;
    }
    if (!registrationVerified && !RegExp(r'^[0-9]{8}$').hasMatch(code.text)) {
      setState(() => error = 'Enter the 8-digit code.');
      return;
    }
    if (reset && (password.text.length < 8 || password.text.length > 128)) {
      setState(() => error = 'Use 8–128 characters for your password.');
      return;
    }
    if (reset && password.text != confirm.text) {
      setState(() => error = 'Your passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      switch (widget.purpose) {
        case EmailAuthPurpose.registration:
          if (!registrationVerified) {
            await widget.auth.verifyRegistration(address, code.text);
            if (!mounted) return;
            setState(() => registrationVerified = true);
            code.clear();
            timer?.cancel();
          }
          final session = await widget.auth.login(address, widget.password);
          if (!mounted) return;
          Navigator.of(context).pop(EmailAuthResult(address, session: session));
        case EmailAuthPurpose.reset:
          await widget.auth.resetPassword(address, code.text, password.text);
          if (mounted) {
            setState(
              () => success = 'Password reset. Log in with your new password.',
            );
          }
        case EmailAuthPurpose.login:
          final session = await widget.auth.verifyLoginCode(
            address,
            code.text,
            temporary: widget.temporaryLogin,
          );
          if (!mounted) {
            if (widget.temporaryLogin) {
              unawaited(widget.auth.revokeTemporary(session));
            }
            return;
          }
          Navigator.of(context).pop(EmailAuthResult(address, session: session));
      }
      code.clear();
      password.clear();
      confirm.clear();
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.message;
          if (failure.retryAfter != null) countdown(failure.retryAfter!);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey(label),
      controller: controller,
      enabled: !busy,
      obscureText: secret && !visible,
      keyboardType: secret
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: !secret,
      maxLength: secret ? 128 : 254,
      autofillHints: secret
          ? const [AutofillHints.newPassword]
          : const [AutofillHints.email],
      decoration: InputDecoration(
        labelText: tr(context, label),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
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
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final title = registrationVerified
        ? 'Account created'
        : success != null
        ? (reset ? 'Password reset' : 'Email verified')
        : registration
        ? 'Verify your email'
        : reset
        ? (sent ? 'Reset your password' : 'Forgot password?')
        : sent
        ? 'Check your email'
        : 'Log in with a code';
    final description = widget.auth.api is DemoAuthApi
        ? 'Local demo only. No email is sent. Use code 12345678. Do not enter real credentials.'
        : registrationVerified
        ? 'Your email is verified. Continue to sign in to your new account.'
        : success != null
        ? (reset
              ? 'Log in with your new password. Your other device sessions have been signed out.'
              : 'Your account is ready. Log in with your email and password to continue.')
        : !sent && !registration
        ? (reset
              ? 'Enter your account email to receive a password reset code.'
              : 'Enter your registered email. We’ll send a code so you can log in without your password.')
        : reset
        ? 'If $address is eligible, a code has been sent. Enter it below and choose a new password.'
        : 'Enter the 8-digit ${registration ? 'verification' : 'login'} code sent to $address.';
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: MediaQuery.orientationOf(context) == Orientation.portrait
              ? Alignment.center
              : Alignment.centerLeft,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              success != null
                  ? Icons.check_rounded
                  : reset
                  ? Icons.lock_reset_outlined
                  : Icons.mark_email_read_outlined,
              color: AppColors.primary,
              size: 34,
            ),
          ),
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
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (success == null && !registrationVerified) ...[
          if (!sent && !registration) field('Email', email),
          if (sent) ...[
            const LText(
              'Verification code',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('Verification code'),
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 8,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: '00000000',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 18,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const LText(
              'Code expires in 5 minutes',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy || cooldown > 0 ? null : send,
                child: LText(
                  cooldown > 0 ? 'Resend code in ${cooldown}s' : 'Resend code',
                ),
              ),
            ),
            if (reset) ...[
              field('New password', password, secret: true),
              field('Confirm password', confirm, secret: true),
              const LText(
                'Use 8–128 characters.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
            ],
          ],
          if (!sent && registration && !busy)
            TextButton(
              onPressed: send,
              child: const LText('Retry sending code'),
            ),
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
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: busy || !sent && cooldown > 0 ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : LText(
                    registrationVerified
                        ? 'Continue'
                        : success != null
                        ? 'Back to Log In'
                        : !sent
                        ? (reset ? 'Send reset code' : 'Send code')
                        : registration
                        ? 'Verify email'
                        : reset
                        ? 'Reset password'
                        : 'Log In',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        if ((!registration || registrationVerified) && success == null)
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: const LText('Back to Log In'),
          ),
      ],
    );
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xff20251b),
                AppColors.background,
                AppColors.background,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: AuthFlowLayout(intro: intro, form: form),
          ),
        ),
      ),
    );
  }
}
