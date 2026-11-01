import 'package:flutter/material.dart';

/// Shared sizing for email verification, recovery and provider-link forms.
/// Tablet controls scale together; keyboard insets only reduce scroll space.
class AuthFlowLayout extends StatelessWidget {
  const AuthFlowLayout({super.key, required this.intro, required this.form});

  final Widget intro;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final tablet = media.size.shortestSide >= 600;
    final wide = media.orientation == Orientation.landscape;
    final scale = tablet
        ? (media.size.shortestSide / 500).clamp(1.0, 1.6)
        : 1.0;
    return LayoutBuilder(
      builder: (context, bounds) => SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: bounds.maxWidth / scale,
            height: bounds.maxHeight / scale,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                wide ? 36 : 24,
                wide ? 24 : 48,
                wide ? 36 : 24,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wide ? 1000 : (tablet ? 600 : 400),
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: intro),
                            const SizedBox(width: 48),
                            Expanded(child: form),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [intro, const SizedBox(height: 36), form],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
