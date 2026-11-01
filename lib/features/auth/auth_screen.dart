import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/app_toast.dart';
import 'package:hand_gesture/shared/layout/responsive_canvas.dart';
import 'package:hand_gesture/shared/layout/landscape_layout.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'social_login_demo.dart';
import 'email_auth_screen.dart';
import 'social_sign_in_screen.dart';
import 'services/auth_api.dart';
import 'services/demo_auth.dart';
import 'services/auth_session.dart';

part 'auth_screen_landscape.dart';

/// Native, editable controls laid out on the Figma 402 × 874 design canvas.
/// Gister authentication in the app; isolated preview builds remain simulated.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.page, this.authUiPreview = false});

  final FlowPage page;
  final bool authUiPreview;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  void _update(VoidCallback change) => setState(change);

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmation = false;
  bool _busy = false;
  String? _error;
  String? _focusedField;

  bool get _signup => widget.page == FlowPage.createAccount;

  @override
  void initState() {
    super.initState();
    _email.text = context.read<GestureController>().authEmailDraft;
    if (!_signup &&
        context.read<GestureController>().auth?.api is DemoAuthApi) {
      if (_email.text.isEmpty) _email.text = DemoAuthApi.email;
      _password.text = DemoAuthApi.password;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<GestureController>();
      final message = c.authMessage;
      c.authMessage = null;
      if (message != null) {
        AppToast.show(context, message);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final splash = widget.page == FlowPage.splash;
    final c = context.read<GestureController>();
    return PopScope(
      canPop: splash,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) c.back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Theme(
            data: AppTheme.auth,
            child: MediaQuery.withClampedTextScaling(
              // The reference's type sizes stay legible when Android uses its
              // small-font setting. Larger accessibility text remains enabled.
              minScaleFactor: 1,
              child: LayoutBuilder(
                builder: (context, viewport) {
                  // Android can report a zero-sized surface during startup or
                  // rotation. Wait for real bounds before dividing by scale.
                  if (viewport.maxWidth <= 0 || viewport.maxHeight <= 0) {
                    return const SizedBox.shrink();
                  }
                  if (landscapeLayout(context)) {
                    return ResponsiveLandscape(builder: (_) => _landscape(c));
                  }
                  final width = portraitCanvasWidth(context, viewport);
                  final scale = portraitCanvasScale(context, viewport);
                  final canvasWidth = width / scale;
                  // Keep the design's spacing on short phones and when the
                  // keyboard opens; the scroll view keeps every field reachable.
                  final height = math.max(874.0, viewport.maxHeight / scale);
                  final expanded = expandedCanvas(context);
                  Widget background() => Image.asset(
                    'assets/auth/${splash
                        ? 'splash'
                        : _signup
                        ? 'signup'
                        : 'auth'}-background.png',
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (expanded) Positioned.fill(child: background()),
                      Center(
                        child: SizedBox(
                          width: width,
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: SizedBox(
                              height: height * scale,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  key: const ValueKey('auth-canvas'),
                                  width: canvasWidth,
                                  height: height,
                                  child: Stack(
                                    children: portraitCanvasChildren([
                                      if (!expanded)
                                        Positioned.fill(child: background()),
                                      if (splash)
                                        ..._splash(c)
                                      else
                                        ..._form(c),
                                    ], canvasWidth),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _splash(GestureController c) => [
    // Exported group includes the original image, labels, arrows, and shadow.
    // The export includes the original shadow outside the group's bounds.
    Positioned(
      left: 19.5,
      top: 140,
      width: 350.5,
      height: 492,
      child: Image.asset(
        'assets/auth/controller-artwork.png',
        semanticLabel: 'Gesture controller with following and gesture control',
      ),
    ),
    Positioned(
      left: 18,
      top: 638,
      width: 366,
      height: 120,
      child: Image.asset(
        'assets/auth/splash-headline.png',
        semanticLabel: 'Turn Every Move Into a Moment',
      ),
    ),
    Positioned(
      left: 19,
      right: 19,
      top: 784,
      height: 44,
      child: _primary('Get Started', () => c.open(FlowPage.login)),
    ),
  ];

  List<Widget> _form(GestureController c) => [
    Positioned(
      left: _signup ? 20 : 18,
      top: _signup ? 143 : 224,
      width: _signup ? 362 : 345,
      child: LText(
        _signup ? 'Create Your Account' : 'Log in and explore\nour machine',
        style: const TextStyle(
          fontFamily: AppTypography.bodyFont,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: AppColors.white,
          letterSpacing: 0,
        ),
      ),
    ),
    if (_signup)
      const Positioned(
        left: 20,
        top: 191,
        child: LText(
          'Create account to continue with all features',
          style: TextStyle(
            fontFamily: AppTypography.bodyFont,
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
      ),
    if (_signup)
      _field(
        top: 238,
        label: 'Full Name',
        controller: _name,
        capitalization: TextCapitalization.words,
      ),
    _field(
      top: _signup ? 308 : 440,
      label: 'Email',
      controller: _email,
      keyboardType: TextInputType.emailAddress,
    ),
    _field(
      top: _signup ? 378 : 510,
      label: 'Password',
      controller: _password,
      password: true,
      visible: _showPassword,
      toggle: () => setState(() => _showPassword = !_showPassword),
      last: !_signup,
    ),
    if (_signup)
      _field(
        top: 448,
        label: 'Confirm Password',
        controller: _confirmation,
        password: true,
        visible: _showConfirmation,
        toggle: () => setState(() => _showConfirmation = !_showConfirmation),
        last: true,
      ),
    Positioned(
      left: _signup ? 127 : 126,
      top: _signup ? 563 : 332,
      width: 148,
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _social('Google', 'google.png'),
          _social('Facebook', 'facebook.png'),
        ],
      ),
    ),
    Positioned(
      left: 0,
      right: 0,
      top: _signup ? 515 : 400,
      height: 24,
      child: const Center(
        child: LText(
          'Or',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontFamily: AppTypography.bodyFont,
            fontSize: 14,
            height: 24 / 14,
            letterSpacing: 0,
          ),
        ),
      ),
    ),
    if (!_signup)
      Positioned(
        left: 0,
        right: 0,
        top: 688,
        height: 24,
        child: Center(
          child: LText(
            'Or',
            style: AppTypography.text(14, 24, color: AppColors.textSecondary),
          ),
        ),
      ),
    if (!_signup)
      Positioned(
        left: 18,
        right: 20,
        top: 728,
        height: 44,
        child: OutlinedButton(
          key: const ValueKey('continue-as-guest'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.white,
            padding: EdgeInsets.zero,
            side: const BorderSide(color: AppColors.white),
            shape: const StadiumBorder(),
            textStyle: AppTypography.text(16, 24, weight: FontWeight.w600),
          ),
          onPressed: _busy ? null : _continueAsGuest,
          child: const LText('Skip -use as guest'),
        ),
      ),
    if (!_signup && context.read<GestureController>().auth != null)
      Positioned(
        left: 18,
        top: 580,
        height: 20,
        child: _textButton(
          'Log in with a code',
          () => _emailFlow(EmailAuthPurpose.login),
          muted: true,
          size: 12,
        ),
      ),
    if (!_signup)
      Positioned(
        right: 20,
        top: 580,
        height: 20,
        child: _textButton('Forgot Password?', _forgotPassword, muted: true),
      ),
    if (_error != null)
      Positioned(
        left: 20,
        right: 20,
        top: _signup ? 620 : 607,
        height: 26,
        child: Semantics(
          liveRegion: true,
          child: LText(
            _error!,
            style: const TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ),
      ),
    Positioned(
      left: _signup ? 20 : 18,
      right: 20,
      top: _signup ? 647 : 632,
      height: 44,
      child: _primary(_signup ? 'Next' : 'Log In', _submit),
    ),
    Positioned(
      left: _signup ? 20 : 18,
      right: 20,
      top: _signup ? 707 : 794,
      height: 24,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LText(
              _signup
                  ? 'Already have an account? '
                  : 'Don’t have any account? ',
              style: const TextStyle(
                color: AppColors.subtleText,
                fontFamily: AppTypography.bodyFont,
                fontSize: 14,
                height: 24 / 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            _textButton(
              _signup ? 'Log In' : 'Create Account',
              () => c.open(_signup ? FlowPage.login : FlowPage.createAccount),
              size: 16,
              weight: FontWeight.w500,
            ),
          ],
        ),
      ),
    ),
  ];

  Widget _field({
    required double top,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    bool password = false,
    bool visible = false,
    VoidCallback? toggle,
    bool last = false,
  }) => Positioned(
    left: _signup ? 20 : 18,
    right: 20,
    top: top,
    height: 44,
    child: _fieldInput(
      label: label,
      controller: controller,
      keyboardType: keyboardType,
      capitalization: capitalization,
      password: password,
      visible: visible,
      toggle: toggle,
      last: last,
    ),
  );

  Widget _fieldInput({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    bool password = false,
    bool visible = false,
    VoidCallback? toggle,
    bool last = false,
  }) => Focus(
    onFocusChange: (focused) {
      if (!mounted) return;
      setState(() {
        if (focused) {
          _focusedField = label;
        } else if (_focusedField == label) {
          _focusedField = null;
        }
      });
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focusedField == label
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
      ),
      alignment: Alignment.center,
      child: TextField(
        key: ValueKey(label),
        controller: controller,
        enabled: !_busy,
        obscureText: password && !visible,
        enableSuggestions: !password,
        autocorrect: !password && keyboardType != TextInputType.emailAddress,
        keyboardType: keyboardType,
        textCapitalization: capitalization,
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        textAlignVertical: TextAlignVertical.center,
        onSubmitted: last ? (_) => _submit() : null,
        scrollPadding: const EdgeInsets.all(32),
        style: const TextStyle(
          fontFamily: AppTypography.bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 20 / 14,
          color: AppColors.white,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          hintText: tr(context, label),
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: AppTypography.bodyFont,
            fontSize: 14,
            height: 20 / 14,
            letterSpacing: 0,
            fontWeight: FontWeight.w400,
          ),
          // Hint and semantic label avoid floating labels absent from Figma.
          isDense: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 24,
            height: 24,
          ),
          suffixIcon: password
              ? IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: tr(context, visible ? 'Hide $label' : 'Show $label'),
                  onPressed: toggle,
                  icon: visible
                      ? const Icon(
                          Icons.visibility_outlined,
                          size: 24,
                          color: AppColors.textSecondary,
                        )
                      : Image.asset(
                          'assets/auth/eye-closed.png',
                          width: 24,
                          height: 24,
                        ),
                )
              : const SizedBox(width: 24, height: 24),
        ),
      ),
    ),
  );

  Widget _primary(String label, VoidCallback onPressed) => FilledButton(
    style: FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      minimumSize: const Size(0, 44),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: AppTypography.bodyFont,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ),
    onPressed: _busy ? null : onPressed,
    child: _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.background,
            ),
          )
        : LText(label),
  );

  Widget _textButton(
    String label,
    VoidCallback onPressed, {
    bool muted = false,
    double size = 14,
    FontWeight weight = FontWeight.w400,
  }) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: muted ? AppColors.textSecondary : AppColors.white,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontFamily: AppTypography.bodyFont,
        fontSize: size,
        height: (size == 14 ? 20 : 24) / size,
        fontWeight: weight,
        letterSpacing: 0,
      ),
    ),
    onPressed: _busy ? null : onPressed,
    child: LText(label),
  );

  Widget _social(String provider, String asset) => IconButton(
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 52, height: 52),
    tooltip: tr(context, 'Continue with $provider'),
    onPressed: _busy
        ? null
        : () => _socialSignIn(
            provider,
            chooseGoogleAccount: provider == 'Google',
          ),
    icon: Image.asset('assets/auth/$asset', width: 52, height: 52),
  );

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    String? error;
    if (_signup && _name.text.trim().isEmpty) {
      error = 'Enter your full name.';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      error = 'Enter a valid email address.';
    } else if (_password.text.isEmpty) {
      error = 'Enter your password.';
    } else if (_signup && _name.text.trim().length > 100) {
      error = 'Use no more than 100 characters for your name.';
    } else if (email.length > 254) {
      error = 'Use a shorter email address.';
    } else if (_signup && _password.text.length < 8) {
      error = 'Use at least 8 characters for your password.';
    } else if (_password.text.length > 128) {
      error = 'Use no more than 128 characters for your password.';
    } else if (_signup && _password.text != _confirmation.text) {
      error = 'Your passwords do not match.';
    }
    setState(() => _error = error);
    if (error != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final c = context.read<GestureController>();
    try {
      if (c.auth == null) {
        // Only isolated preview/test hosts omit the authentication service.
        await c.signInDemo(_signup ? _name.text : email.split('@').first);
      } else if (_signup) {
        await _emailFlow(EmailAuthPurpose.registration);
      } else {
        final session = await c.auth!.login(email, _password.text);
        _password.clear();
        if (mounted) await c.acceptAuthSession(session);
      }
    } on AuthFailure catch (failure) {
      if (mounted) {
        AppToast.show(context, failure.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<GestureController>().continueAsGuest();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _socialSignIn(
    String provider, {
    bool chooseGoogleAccount = false,
  }) async {
    if (widget.authUiPreview) {
      FocusScope.of(context).unfocus();
      final result = await Navigator.of(context).push<SocialDemoResult>(
        MaterialPageRoute(builder: (_) => SocialLoginDemo(provider: provider)),
      );
      if (!mounted) return;
      if (result == SocialDemoResult.existing ||
          result == SocialDemoResult.newAccount) {
        await context.read<GestureController>().signInDemo(
          result == SocialDemoResult.newAccount ? 'New user' : 'Demo user',
        );
      } else {
        AppToast.show(
          context,
          result == SocialDemoResult.failed
              ? '$provider sign-in failed. Please try again.'
              : '$provider sign-in cancelled.',
        );
      }
      return;
    }
    final c = context.read<GestureController>();
    final auth = c.auth;
    if (auth == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await Navigator.of(context).push<Object>(
        MaterialPageRoute(
          builder: (_) => SocialSignInScreen(
            auth: auth,
            provider: provider.toLowerCase(),
            chooseGoogleAccount: chooseGoogleAccount,
          ),
        ),
      );
      if (!mounted) return;
      if (result is AuthSession) {
        await c.acceptAuthSession(result);
      } else {
        AppToast.show(
          context,
          result is AuthFailure
              ? result.message
              : '$provider sign-in cancelled.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgotPassword() => _emailFlow(EmailAuthPurpose.reset);

  Future<void> _emailFlow(EmailAuthPurpose purpose) async {
    final c = context.read<GestureController>();
    final auth = c.auth;
    if (auth == null) return;
    final result = await Navigator.of(context).push<EmailAuthResult>(
      MaterialPageRoute(
        builder: (_) => EmailAuthScreen(
          auth: auth,
          purpose: purpose,
          email: _email.text.trim(),
          name: _name.text.trim(),
          password: purpose == EmailAuthPurpose.registration
              ? _password.text
              : '',
        ),
      ),
    );
    if (!mounted) return;
    if (purpose == EmailAuthPurpose.registration) {
      _password.clear();
      _confirmation.clear();
    }
    if (result == null) return;
    _email.text = result.email;
    c.authEmailDraft = result.email;
    if (result.session != null) {
      await c.acceptAuthSession(result.session!);
    } else {
      c.open(FlowPage.login);
      if (result.message != null) {
        AppToast.show(context, result.message!);
      }
    }
  }
}
