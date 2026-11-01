import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/l10n/app_strings.dart';

/// Uses installed build metadata, including Flutter build-name/number overrides.
class SoftwareVersionText extends StatefulWidget {
  static const channel = MethodChannel('lazivoo/app_info');
  const SoftwareVersionText({super.key, required this.style});
  final TextStyle style;

  @override
  State<SoftwareVersionText> createState() => _SoftwareVersionTextState();
}

class _SoftwareVersionTextState extends State<SoftwareVersionText> {
  late final Future<String?> _version = _loadVersion();

  Future<String?> _loadVersion() async {
    try {
      final info = await SoftwareVersionText.channel
          .invokeMapMethod<String, dynamic>('getVersion');
      final version = info?['version'] as String? ?? '';
      final build = info?['buildNumber'] as String? ?? '';
      if (version.isEmpty) return null;
      return build.isEmpty ? version : '$version+$build';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _version,
    builder: (context, snapshot) =>
        LText('Software Version: ${snapshot.data ?? '—'}', style: widget.style),
  );
}
