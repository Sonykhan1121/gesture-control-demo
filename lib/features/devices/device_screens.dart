import 'package:hand_gesture/shared/app_dialog.dart';
import 'package:hand_gesture/shared/logout_confirmation.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/layout/responsive_canvas.dart';
import 'package:hand_gesture/shared/layout/landscape_layout.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'bluetooth_setup_dialog.dart';

part 'device_screens_landscape.dart';

class DeviceScreens extends StatefulWidget {
  const DeviceScreens({super.key, required this.page});
  final FlowPage page;

  @override
  State<DeviceScreens> createState() => _DeviceScreensState();
}

class _DeviceScreensState extends State<DeviceScreens> {
  void _update(VoidCallback change) => setState(change);

  bool _connecting = false;
  BluetoothSetupIssue? _lastSetupIssue;
  bool _showBluetoothHelp = true;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GestureController>();
    final issue = c.discovery.setupIssue;
    if (_lastSetupIssue != issue) {
      _lastSetupIssue = issue;
      _showBluetoothHelp = true;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Theme(
                data: AppTheme.screen,
                child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: 1,
                  child: LayoutBuilder(
                    builder: (context, viewport) {
                      if (landscapeLayout(context)) {
                        return ResponsiveLandscape(
                          builder: (_) => _landscape(c),
                        );
                      }
                      final width = portraitCanvasWidth(context, viewport);
                      final scale = portraitCanvasScale(context, viewport);
                      final canvasWidth = width / scale;
                      final height = math.max(
                        874.0,
                        viewport.maxHeight / scale,
                      );
                      return Center(
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
                                  width: canvasWidth,
                                  height: height,
                                  child: Stack(
                                    children: portraitCanvasChildren(
                                      widget.page == FlowPage.home
                                          ? _home(context, c)
                                          : _addDevice(c),
                                      canvasWidth,
                                      topOffset: portraitHeaderOffset(
                                        context,
                                        scale,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (widget.page == FlowPage.connect &&
                  c.connectionMethod == 'Auto' &&
                  issue != null &&
                  _showBluetoothHelp)
                Positioned.fill(
                  child: BlockSemantics(
                    child: Stack(
                      children: [
                        const ModalBarrier(
                          dismissible: false,
                          color: Colors.black54,
                        ),
                        Center(
                          child: BluetoothSetupDialog(
                            key: ValueKey(issue),
                            issue: issue,
                            onLater: () =>
                                setState(() => _showBluetoothHelp = false),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (widget.page == FlowPage.connect &&
                  c.connectionMethod == 'Auto' &&
                  c.discovery.scanning)
                _searchDialog(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchDialog(GestureController c) => Positioned.fill(
    child: BlockSemantics(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: AppDialog(
              key: const ValueKey('bluetooth-search-dialog'),
              icon: Icons.bluetooth_searching_rounded,
              leading: const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              ),
              title: c.discovery.waitingForBluetooth
                  ? 'Getting Bluetooth ready'
                  : 'Searching for nearby Bluetooth device',
              message: c.discovery.waitingForBluetooth
                  ? 'If your iPhone asks, allow lazivoo to use Bluetooth.'
                  : null,
              actions: [
                appDialogAction(
                  'Cancel',
                  c.discovery.cancelScan,
                  primary: false,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _home(BuildContext context, GestureController c) => [
    Positioned(
      left: 19.5,
      top: 61,
      width: 243,
      height: 46,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText('Hello!', style: AppTypography.text(12, 18)),
          Text(
            c.preferences.getBool('gesture.guestSession') == true
                ? tr(context, 'Guest')
                : c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.text(20, 28, weight: FontWeight.w500),
          ),
        ],
      ),
    ),
    Positioned(
      left: 278.5,
      top: 62,
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tr(context, 'Settings'),
        padding: EdgeInsets.zero,
        onPressed: () => c.openSettings(returnTo: FlowPage.home),
        icon: Image.asset(
          'assets/devices/settings-button.png',
          width: 44,
          height: 44,
        ),
      ),
    ),
    Positioned(
      left: 338.5,
      top: 62,
      width: 44,
      height: 44,
      child: PopupMenuButton<String>(
        tooltip: tr(context, 'Profile'),
        color: AppColors.surface,
        padding: EdgeInsets.zero,
        onSelected: (value) {
          if (value == 'logout') confirmLogout(context, c);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Text(
              c.preferences.getBool('gesture.guestSession') == true
                  ? tr(context, 'Guest')
                  : c.name,
              style: AppTypography.text(16, 24),
            ),
          ),
          PopupMenuItem(
            value: 'logout',
            child: LText('Log out', style: AppTypography.text(14, 20)),
          ),
        ],
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            c.name.trim().isEmpty
                ? 'G'
                : c.name.trim().characters.first.toUpperCase(),
            style: AppTypography.text(24, 32),
          ),
        ),
      ),
    ),
    Positioned(
      left: 20,
      top: 169,
      width: 362,
      height: 192,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            SizedBox(
              width: 80,
              height: 80,
              child: IconButton(
                tooltip: tr(context, 'Add a device'),
                padding: EdgeInsets.zero,
                onPressed: () => c.chooseConnection('Auto'),
                icon: Image.asset(
                  'assets/devices/add-device-icon.png',
                  width: 80,
                  height: 80,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: _button('Add Device', () => c.chooseConnection('Auto')),
              ),
            ),
          ],
        ),
      ),
    ),
    if (c.device != null)
      Positioned(
        left: 20,
        right: 20,
        top: 385,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          child: ListTile(
            leading: Image.asset(
              'assets/devices/controller-thumbnail.png',
              width: 46,
              height: 44,
            ),
            title: Text(c.device!, style: AppTypography.text(14, 20)),
            subtitle: LText(
              c.trained ? 'Saved demo setup' : 'Continue setup',
              style: AppTypography.text(12, 18, color: AppColors.textSecondary),
            ),
            trailing: const Icon(
              CupertinoIcons.chevron_right,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onTap: c.resumeSetup,
          ),
        ),
      ),
  ];

  List<Widget> _addDevice(GestureController c) {
    final manual = c.connectionMethod != 'Auto';
    return [
      Positioned(
        left: 20,
        top: 62,
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tr(context, 'Back'),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            shape: const CircleBorder(),
          ),
          onPressed: c.back,
          icon: const Icon(
            CupertinoIcons.chevron_back,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
      if (!manual)
        Positioned(
          right: 20,
          top: 62,
          width: 44,
          height: 44,
          child: IconButton(
            key: const ValueKey('refresh-bluetooth'),
            tooltip: tr(context, 'Refresh Bluetooth search'),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface,
              shape: const CircleBorder(),
            ),
            onPressed: c.refreshAutoSearch,
            icon: const Icon(
              CupertinoIcons.refresh,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
        ),
      Positioned(
        left: 76,
        right: 76,
        top: 68,
        height: 32,
        child: Center(
          child: LText(
            'Add device',
            style: AppTypography.text(24, 32, weight: FontWeight.w700),
          ),
        ),
      ),
      Positioned(
        left: 111,
        top: 141,
        width: 180,
        height: 38,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _modeTab('Auto', !manual, () => c.chooseConnection('Auto')),
              _modeTab('Manually', manual, () => c.chooseConnection('Manual')),
            ],
          ),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        top: 215,
        bottom: 20,
        child: manual
            ? Column(children: [_manualCard(c)])
            : _hasStandaloneSearchError(c)
            ? _centeredSearchError(c)
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (
                    var index = 0;
                    index < c.discovery.devices.length;
                    index++
                  )
                    _deviceRow(c, c.discovery.devices[index], index),
                  if (c.discovery.setupIssue != null)
                    BluetoothSetupCard(
                      issue: c.discovery.setupIssue!,
                      onHelp: () => setState(() => _showBluetoothHelp = true),
                    ),
                  if (c.connectionError != null ||
                      (c.discovery.error != null &&
                          c.discovery.setupIssue == null))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: LText(
                        (c.connectionError ?? c.discovery.error)!,
                        style: AppTypography.text(
                          12,
                          18,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  if (!c.discovery.scanning &&
                      c.discovery.devices.isEmpty &&
                      c.discovery.error == null)
                    LText(
                      'No Bluetooth devices found',
                      textAlign: TextAlign.center,
                      style: AppTypography.text(
                        12,
                        18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
      ),
    ];
  }

  bool _hasStandaloneSearchError(GestureController c) =>
      c.discovery.setupIssue == null &&
      c.discovery.devices.isEmpty &&
      (c.connectionError ?? c.discovery.error) != null;

  Widget _centeredSearchError(GestureController c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LText(
          (c.connectionError ?? c.discovery.error)!,
          textAlign: TextAlign.center,
          style: AppTypography.text(16, 24, color: AppColors.error),
        ),
      ),
    ),
  );

  Widget _manualCard(GestureController c) => Center(
    child: SizedBox(
      width: 100,
      height: 100,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('manual-gesture-control'),
          onTap: _connecting ? null : () => _connect(c),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/devices/controller-thumbnail.png',
                width: 80,
                height: 50,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 6),
              LText(
                'Gesture Control',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.text(10, 15, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _modeTab(String label, bool selected, VoidCallback onTap) => Expanded(
    child: TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: selected ? AppColors.primary : AppColors.transparent,
        foregroundColor: selected
            ? AppColors.background
            : AppColors.textPrimary,
        shape: const StadiumBorder(),
        textStyle: AppTypography.text(
          label == 'Auto' ? 16 : 12,
          label == 'Auto' ? 24 : 18,
        ),
      ),
      onPressed: onTap,
      child: LText(label),
    ),
  );

  Widget _deviceRow(GestureController c, DiscoveredDevice device, int index) =>
      Container(
        key: ValueKey(device.address),
        height: 64,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.surface)),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/devices/controller-thumbnail.png',
              width: 46,
              height: 44,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.text(
                      12,
                      18,
                      weight: FontWeight.w500,
                      family: AppTypography.detailFont,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LText(
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? 'Device ID: ${device.address}'
                        : 'MAC Address: ${device.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.text(
                      8,
                      12,
                      family: AppTypography.detailFont,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 88,
              height: 40,
              child: _button(
                'Connect',
                () => _connect(c, deviceName: device.name),
                key: ValueKey('connect-$index'),
              ),
            ),
          ],
        ),
      );

  Widget _button(String text, VoidCallback action, {Key? key}) => FilledButton(
    key: key,
    onPressed: _connecting ? null : action,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      shape: const StadiumBorder(),
      textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
    ),
    child: LText(text),
  );

  Future<void> _connect(GestureController c, {String? deviceName}) async {
    if (_connecting) return;
    // A tap can arrive from the previous frame just after the adapter went off.
    if (deviceName != null && c.discovery.error != null) return;
    setState(() => _connecting = true);
    await c.connectDemoDevice(deviceName: deviceName);
    if (mounted) setState(() => _connecting = false);
  }
}
