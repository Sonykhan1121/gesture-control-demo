import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/app_toast.dart';
import 'dart:async';

import 'auth_flow_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'services/auth_api.dart';
import 'services/auth_service.dart';
import 'services/auth_session.dart';
import 'email_auth_screen.dart';

enum _SocialStep { connecting, linkAccount, linkLogin, linkConfirm, email, otp }

/// Real service behind the approved social flow; the provider owns account choice.
class SocialSignInScreen extends StatefulWidget {
  const SocialSignInScreen({
    super.key,
    required this.auth,
    required this.provider,
    this.chooseGoogleAccount = false,
  });
  final AuthService auth;
  final String provider;
  final bool chooseGoogleAccount;
  @override
  State<SocialSignInScreen> createState() => _SocialSignInScreenState();
}

class _SocialSignInScreenState extends State<SocialSignInScreen> {
  _SocialStep step = _SocialStep.connecting;
  final email = TextEditingController();
  final password = TextEditingController();
  final otp = TextEditingController();
  AuthSession? _linkSession;
  PendingSocial? _pending;
  bool busy = true, visible = false, _completed = false;
  String? error;
  int cooldown = 0;
  Timer? _timer;
  DateTime? _resendAt;
  String get provider => widget.provider == 'google' ? 'Google' : 'Facebook';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(begin());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.auth.cancelAttempt();
    final temporary = _linkSession;
    if (!_completed && temporary != null) {
      unawaited(widget.auth.revokeTemporary(temporary));
    }
    email.dispose();
    password.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> begin({bool linking = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final pending = await widget.auth.authorize(
        widget.provider,
        linkSession: linking ? _linkSession : null,
        chooseGoogleAccount: widget.chooseGoogleAccount,
      );
      if (!mounted) return;
      _pending = pending;
      if (pending.needsEmail) {
        setState(() => step = _SocialStep.email);
      } else {
        await complete();
      }
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      if (failure.code == 'ACCOUNT_LINK_REQUIRED') {
        setState(() => step = _SocialStep.linkAccount);
      } else {
        Navigator.of(context).pop(failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> complete() async {
    final pending = _pending;
    if (pending == null) throw const AuthFailure('FLOW_EXPIRED');
    try {
      final session = await widget.auth.exchange(pending);
      if (!mounted) return;
      _completed = true;
      final old = _linkSession;
      if (old != null && old.sessionId != session.sessionId) {
        unawaited(widget.auth.revokeTemporary(old));
      }
      Navigator.of(context).pop(session);
    } on AuthFailure catch (failure) {
      if (failure.code == 'SOCIAL_EMAIL_VERIFICATION_REQUIRED' && mounted) {
        pending.needsEmail = true;
        setState(() => step = _SocialStep.email);
      } else {
        rethrow;
      }
    }
  }

  void startCooldown([int seconds = 60]) {
    _timer?.cancel();
    cooldown = seconds.clamp(1, 3600);
    _resendAt = DateTime.now().add(Duration(seconds: cooldown));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => cooldown =
            (_resendAt!.difference(DateTime.now()).inMilliseconds / 1000)
                .ceil()
                .clamp(0, 3600),
      );
      if (cooldown <= 0) timer.cancel();
    });
  }

  bool validEmail() {
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      return true;
    }
    setState(() => error = 'Enter a valid email address.');
    return false;
  }

  Future<void> sendEmail({bool resend = false}) async {
    if (busy || !validEmail()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final pending = _pending;
      if (pending == null) throw const AuthFailure('FLOW_EXPIRED');
      await widget.auth.requestSocialEmail(pending, email.text);
      if (!mounted) return;
      setState(() {
        step = _SocialStep.otp;
        startCooldown();
      });
      if (resend) {
        AppToast.show(context, 'A new verification code has been requested.');
      }
    } on AuthFailure catch (failure) {
      if (mounted && failure.code == 'ACCOUNT_LINK_REQUIRED') {
        setState(() {
          step = _SocialStep.linkAccount;
          error = null;
        });
      } else if (mounted) {
        setState(() {
          error = failure.message;
          if (failure.retryAfter != null) startCooldown(failure.retryAfter!);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    if (step == _SocialStep.linkAccount) {
      setState(() => step = _SocialStep.linkLogin);
      return;
    }
    if (step == _SocialStep.linkConfirm) {
      await begin(linking: true);
      return;
    }
    if (step == _SocialStep.email) {
      await sendEmail();
      return;
    }
    if (step == _SocialStep.linkLogin &&
        (!validEmail() || password.text.isEmpty)) {
      if (password.text.isEmpty) setState(() => error = 'Enter your password.');
      return;
    }
    if (step == _SocialStep.otp && !RegExp(r'^[0-9]{8}$').hasMatch(otp.text)) {
      setState(() => error = 'Enter the 8-digit code.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (step == _SocialStep.linkLogin) {
        final session = await widget.auth.loginForLink(
          email.text,
          password.text,
        );
        password.clear();
        if (!mounted) {
          unawaited(widget.auth.revokeTemporary(session));
          return;
        }
        _linkSession = session;
        setState(() => step = _SocialStep.linkConfirm);
      } else if (step == _SocialStep.otp) {
        final pending = _pending;
        if (pending == null) throw const AuthFailure('FLOW_EXPIRED');
        await widget.auth.verifySocialEmail(pending, otp.text);
        if (mounted) await complete();
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        if (failure.code == 'ACCOUNT_LINK_REQUIRED') {
          setState(() {
            step = _SocialStep.linkAccount;
            error = null;
          });
        } else if (_pending != null && !widget.auth.attemptActive(_pending!)) {
          Navigator.of(context).pop(failure);
        } else {
          setState(() => error = failure.message);
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loginWithCode() async {
    final result = await Navigator.of(context).push<EmailAuthResult>(
      MaterialPageRoute(
        builder: (_) => EmailAuthScreen(
          auth: widget.auth,
          purpose: EmailAuthPurpose.login,
          email: email.text,
          temporaryLogin: true,
        ),
      ),
    );
    if (result?.session == null) return;
    if (!mounted) {
      unawaited(widget.auth.revokeTemporary(result!.session!));
      return;
    }
    email.text = result!.email;
    password.clear();
    _linkSession = result.session;
    setState(() {
      step = _SocialStep.linkConfirm;
      error = null;
    });
  }

  (String, String, String) get copy => switch (step) {
    _SocialStep.connecting => (
      'Continue with $provider',
      'Choose your account in the secure $provider sign-in window.',
      '',
    ),
    _SocialStep.linkAccount => (
      'You already have an account',
      'An account already uses this email. Log in to that account first, then choose whether to link $provider.',
      'Log in to existing account',
    ),
    _SocialStep.linkLogin => (
      'Log in to link $provider',
      'Use your existing account password. $provider will only be linked after your confirmation.',
      'Continue',
    ),
    _SocialStep.linkConfirm => (
      'Link $provider?',
      'Allow your $provider account to log in to your existing account at ${email.text.trim()}?',
      'Link $provider account',
    ),
    _SocialStep.email => (
      'Verify your email',
      'Your sign-in provider needs email verification. Confirm your email to continue.',
      'Send code',
    ),
    _SocialStep.otp => (
      'Check your email',
      'Enter the 8-digit verification code sent to ${email.text.trim()}.',
      'Verify and continue',
    ),
  };

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
      keyboardType: secret
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
      obscureText: secret && !visible,
      autocorrect: false,
      enableSuggestions: !secret,
      maxLength: secret ? 128 : 254,
      autofillHints: secret
          ? const [AutofillHints.password]
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
    final (title, description, action) = copy;
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: MediaQuery.orientationOf(context) == Orientation.portrait
              ? Alignment.center
              : Alignment.centerLeft,
          child: Image.asset(
            'assets/auth/${widget.provider}.png',
            width: 64,
            height: 64,
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
        if (step == _SocialStep.linkLogin || step == _SocialStep.email)
          field('Email', email),
        if (step == _SocialStep.linkLogin)
          field('Password', password, secret: true),
        if (step == _SocialStep.linkLogin)
          TextButton(
            onPressed: busy ? null : loginWithCode,
            child: const LText('Log in with a code'),
          ),
        if (step == _SocialStep.otp) ...[
          const LText(
            'Verification code',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('Verification code'),
            controller: otp,
            enabled: !busy,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
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
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 18),
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
              onPressed: busy || cooldown > 0
                  ? null
                  : () => sendEmail(resend: true),
              child: LText(
                cooldown > 0 ? 'Resend code in ${cooldown}s' : 'Resend code',
              ),
            ),
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
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (action.isNotEmpty)
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: busy ? null : submit,
              child: LText(
                action,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (step == _SocialStep.linkConfirm)
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).pop(),
            child: const LText('Not now'),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: LText('$provider sign-in')),
      body: SafeArea(
        child: AuthFlowLayout(intro: intro, form: form),
      ),
    );
  }
}
