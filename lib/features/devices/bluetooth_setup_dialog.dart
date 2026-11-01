import 'package:hand_gesture/shared/app_dialog.dart';
import 'package:hand_gesture/l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'device_discovery.dart';

extension BluetoothSetupText on BluetoothSetupIssue {
  String get title => switch (this) {
    BluetoothSetupIssue.poweredOff => 'Turn on Bluetooth',
    BluetoothSetupIssue.permissionDenied => 'Allow Bluetooth access',
    BluetoothSetupIssue.unavailable => 'Bluetooth unavailable',
  };

  IconData get icon => switch (this) {
    BluetoothSetupIssue.poweredOff => Icons.bluetooth_disabled_rounded,
    BluetoothSetupIssue.permissionDenied => Icons.lock_outline_rounded,
    BluetoothSetupIssue.unavailable => Icons.bluetooth_disabled_rounded,
  };

  String get description => switch (this) {
    BluetoothSetupIssue.poweredOff =>
      'Enable Bluetooth on your iPhone to find nearby devices.',
    BluetoothSetupIssue.permissionDenied =>
      'Allow lazivoo to use Bluetooth to find nearby devices.',
    BluetoothSetupIssue.unavailable =>
      'Bluetooth search is not available on this device. You can use manual setup instead.',
  };
}

/// Remains on Add Device after dismissing help, so the next action stays clear.
class BluetoothSetupCard extends StatelessWidget {
  const BluetoothSetupCard({
    super.key,
    required this.issue,
    required this.onHelp,
  });
  final BluetoothSetupIssue issue;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('bluetooth-setup-card'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(issue.icon, color: AppColors.primary, size: 28),
        const SizedBox(height: 12),
        LText(
          issue.title,
          style: AppTypography.text(18, 26, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LText(
          issue.description,
          style: AppTypography.text(14, 21, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const ValueKey('bluetooth-show-help'),
          onPressed: onHelp,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: LText(
            issue == BluetoothSetupIssue.unavailable
                ? 'View options'
                : 'Show instructions',
          ),
        ),
      ],
    ),
  );
}

/// Uses the public app-settings link only for permission. The power guidance
/// never implies that an app-settings button can enable the Bluetooth radio.
class BluetoothSetupDialog extends StatefulWidget {
  const BluetoothSetupDialog({
    super.key,
    required this.issue,
    required this.onLater,
    this.openSettings,
  });
  final BluetoothSetupIssue issue;
  final VoidCallback onLater;
  final Future<bool> Function()? openSettings;

  @override
  State<BluetoothSetupDialog> createState() => _BluetoothSetupDialogState();
}

class _BluetoothSetupDialogState extends State<BluetoothSetupDialog> {
  bool _opening = false, _settingsFailed = false;

  Future<void> _openSettings() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _settingsFailed = false;
    });
    var opened = false;
    try {
      opened = await (widget.openSettings ?? openAppSettings)();
    } catch (_) {
      /* Show manual path below. */
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _settingsFailed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final permission = issue == BluetoothSetupIssue.permissionDenied;
    final unavailable = issue == BluetoothSetupIssue.unavailable;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: AppDialog(
        key: const ValueKey('bluetooth-setup-dialog'),
        title: issue.title,
        icon: issue.icon,
        message: issue.description,
        content: unavailable && !_settingsFailed
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!unavailable) ...[
                    _step(
                      '1',
                      permission ? 'Open app settings' : 'Open Control Center',
                      permission
                          ? 'Tap the button below to open lazivoo’s settings.'
                          : 'Swipe down from the top-right corner. On an iPhone with a Home button, swipe up from the bottom.',
                    ),
                    const SizedBox(height: 18),
                    _step(
                      '2',
                      permission ? 'Allow Bluetooth' : 'Make Bluetooth blue',
                      permission
                          ? 'Turn on Bluetooth access for lazivoo, then return to the app.'
                          : 'Touch and hold the connection controls, then tap Bluetooth so the button turns blue.',
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: LText(
                        permission
                            ? 'You can also allow lazivoo in Settings → Privacy & Security → Bluetooth.'
                            : 'You can also go to Settings → Bluetooth and turn Bluetooth on.',
                        style: AppTypography.text(
                          13,
                          20,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    LText(
                      'Return to lazivoo. Searching will start automatically.',
                      textAlign: TextAlign.center,
                      style: AppTypography.text(
                        14,
                        21,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (_settingsFailed) ...[
                    const SizedBox(height: 14),
                    Semantics(
                      liveRegion: true,
                      child: LText(
                        'Couldn’t open Settings. Open Settings → Privacy & Security → Bluetooth and allow lazivoo.',
                        key: const ValueKey('bluetooth-settings-error'),
                        style: AppTypography.text(
                          13,
                          20,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
        actions: [
          if (permission)
            appDialogAction('Not now', widget.onLater, primary: false),
          appDialogAction(
            _opening
                ? 'Opening Settings…'
                : permission
                ? 'Open app settings'
                : unavailable
                ? 'Got it'
                : 'Got it, keep waiting',
            _opening
                ? null
                : permission
                ? _openSettings
                : widget.onLater,
            key: const ValueKey('bluetooth-setup-primary'),
          ),
        ],
      ),
    );
  }

  Widget _step(String number, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: LText(
          number,
          style: AppTypography.text(
            14,
            20,
            weight: FontWeight.w700,
            color: AppColors.darkText,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              title,
              style: AppTypography.text(15, 22, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            LText(
              body,
              style: AppTypography.text(13, 20, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ],
  );
}
