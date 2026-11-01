part of 'auth_screen.dart';

extension _AuthLandscape on _AuthScreenState {
  Widget _landscape(GestureController c) {
    final splash = widget.page == FlowPage.splash;
    Widget field(
      String label,
      TextEditingController controller, {
      bool password = false,
      bool visible = false,
      VoidCallback? toggle,
      bool last = false,
    }) => SizedBox(
      height: 44,
      child: _fieldInput(
        label: label,
        controller: controller,
        password: password,
        visible: visible,
        toggle: toggle,
        last: last,
        keyboardType: label == 'Email' ? TextInputType.emailAddress : null,
        capitalization: label == 'Full Name'
            ? TextCapitalization.words
            : TextCapitalization.none,
      ),
    );
    return Stack(
      key: ValueKey('landscape-${widget.page.name}'),
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/auth/${splash
                ? 'splash'
                : _signup
                ? 'signup'
                : 'auth'}-background.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(300, bounds.maxHeight),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: splash
                            ? Image.asset(
                                'assets/auth/controller-artwork.png',
                                height: 290,
                                semanticLabel:
                                    'Gesture controller with following and gesture control',
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LText(
                                    _signup
                                        ? 'Create Your Account'
                                        : 'Log in and explore\nour machine',
                                    style: AppTypography.text(
                                      27,
                                      35,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  if (_signup) ...[
                                    const SizedBox(height: 8),
                                    LText(
                                      'Create account to continue with all features',
                                      style: AppTypography.text(
                                        13,
                                        19,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _social('Google', 'google.png'),
                                      const SizedBox(width: 18),
                                      _social('Facebook', 'facebook.png'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  LText(
                                    'Or',
                                    style: AppTypography.text(
                                      12,
                                      18,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      LText(
                                        _signup
                                            ? 'Already have an account? '
                                            : 'Don’t have any account? ',
                                        style: AppTypography.text(
                                          12,
                                          20,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      _textButton(
                                        _signup ? 'Log In' : 'Create Account',
                                        () => c.open(
                                          _signup
                                              ? FlowPage.login
                                              : FlowPage.createAccount,
                                        ),
                                        size: 12,
                                        weight: FontWeight.w600,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        flex: 6,
                        child: splash
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/auth/splash-headline.png',
                                    semanticLabel:
                                        'Turn Every Move Into a Moment',
                                  ),
                                  const SizedBox(height: 36),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _primary(
                                      'Get Started',
                                      () => c.open(FlowPage.login),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_signup) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: field('Full Name', _name),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(child: field('Email', _email)),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: field(
                                            'Password',
                                            _password,
                                            password: true,
                                            visible: _showPassword,
                                            toggle: () => _update(
                                              () => _showPassword =
                                                  !_showPassword,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: field(
                                            'Confirm Password',
                                            _confirmation,
                                            password: true,
                                            visible: _showConfirmation,
                                            toggle: () => _update(
                                              () => _showConfirmation =
                                                  !_showConfirmation,
                                            ),
                                            last: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    field('Email', _email),
                                    const SizedBox(height: 14),
                                    field(
                                      'Password',
                                      _password,
                                      password: true,
                                      visible: _showPassword,
                                      toggle: () => _update(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      last: true,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (c.auth != null)
                                          _textButton(
                                            'Log in with a code',
                                            () => _emailFlow(
                                              EmailAuthPurpose.login,
                                            ),
                                            muted: true,
                                            size: 12,
                                          ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: _textButton(
                                            'Forgot Password?',
                                            _forgotPassword,
                                            muted: true,
                                            size: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_error != null) ...[
                                    const SizedBox(height: 10),
                                    Semantics(
                                      liveRegion: true,
                                      child: LText(
                                        _error!,
                                        style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      if (!_signup) ...[
                                        Expanded(
                                          child: landscapeAction(
                                            'Skip -use as guest',
                                            _busy ? null : _continueAsGuest,
                                            secondary: true,
                                            key: const ValueKey(
                                              'continue-as-guest',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: _primary(
                                          _signup ? 'Next' : 'Log In',
                                          _submit,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
