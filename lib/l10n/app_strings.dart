import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Catalogs translate presentation only. Models/API identifiers stay English.
class AppStrings {
  AppStrings(this.language, this.messages);
  static const _labelTemplates = {
    'Show your {0} hand to the camera',
    'Show your {0} hand clearly',
    'Use your {0} hand',
    'Please use your {0} hand',
    'Current mode: {0}. Change mode',
    '{0} mode',
    'Mode changed to {0}',
    '{0} Hand',
    'Reaction color {0}',
    'Wrong hand: detected {0}, selected {1}',
    '{0} hand: {1}',
    'Showing {0}',
    'Your {0} eye\n{1}',
    'Show {0}',
    'Hide {0}',
    '{0} hand {1} placement outline',
  };
  final String language;
  final Map<String, String> messages;
  final Map<String, RegExp> _patterns = {};
  static const names = <String, String>{
    'en': 'English',
    'zh': '简体中文',
    'ja': '日本語',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    'fil': 'Filipino',
    'pt': 'Português',
  };
  static const delegate = _AppStringsDelegate();
  static List<Locale> get locales => names.keys.map(Locale.new).toList();
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings) ?? AppStrings('en', {});

  String text(String source) {
    if (language == 'en') return source;
    final exact = messages[source];
    if (exact != null) return exact;
    for (final entry in messages.entries) {
      if (!entry.key.contains(RegExp(r'\{\d+\}'))) continue;
      final pattern = _patterns.putIfAbsent(entry.key, () {
        final parts = entry.key.split(RegExp(r'\{\d+\}'));
        return RegExp(
          '^${parts.map(RegExp.escape).join('(.*?)')}\$',
          dotAll: true,
        );
      });
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      return entry.value.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final index = int.parse(m[1]!) + 1;
        final value = index <= match.groupCount ? match[index]! : '';
        // Only these templates contain controlled UI labels. Device names,
        // emails and other user values in all other templates stay verbatim.
        if (!_labelTemplates.contains(entry.key)) return value;
        return messages[value] ??
            (value == 'left'
                ? messages['Left']
                : value == 'right'
                ? messages['Right']
                : null) ??
            value;
      });
    }
    return source;
  }
}

String tr(BuildContext context, String source) =>
    AppStrings.of(context).text(source);

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();
  @override
  bool isSupported(Locale locale) =>
      AppStrings.names.containsKey(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) {
    if (locale.languageCode == 'en') {
      return SynchronousFuture(AppStrings('en', {}));
    }
    return _load(locale);
  }

  Future<AppStrings> _load(Locale locale) async {
    final json =
        jsonDecode(
              await rootBundle.loadString(
                'assets/l10n/${locale.languageCode}.json',
              ),
            )
            as Map<String, dynamic>;
    return AppStrings(locale.languageCode, json.cast<String, String>());
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

/// Keeps const widget declarations and localizes when the locale changes.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel, semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : tr(context, semanticsLabel!),
    semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
