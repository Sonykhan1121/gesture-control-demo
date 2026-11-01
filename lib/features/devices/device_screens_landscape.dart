part of 'device_screens.dart';

extension _DevicesLandscape on _DeviceScreensState {
  Widget _landscape(GestureController c) {
    if (widget.page == FlowPage.home) return _landscapeHome(c);
    final manual = c.connectionMethod != 'Auto';
    return LandscapePage(
      key: const ValueKey('landscape-connect'),
      title: 'Add device',
      onBack: c.back,
      action: manual
          ? null
          : IconButton(
              key: const ValueKey('refresh-bluetooth'),
              tooltip: tr(context, 'Refresh Bluetooth search'),
              onPressed: c.refreshAutoSearch,
              icon: const Icon(CupertinoIcons.refresh, size: 22),
            ),
      child: Column(
        children: [
          Container(
            width: 210,
            height: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _modeTab('Auto', !manual, () => c.chooseConnection('Auto')),
                _modeTab(
                  'Manually',
                  manual,
                  () => c.chooseConnection('Manual'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => !manual && _hasStandaloneSearchError(c)
                  ? _centeredSearchError(c)
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (manual)
                          Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: (box.maxWidth - 24) / 2,
                              child: _landscapeManual(c),
                            ),
                          )
                        else ...[
                          Wrap(
                            spacing: 24,
                            runSpacing: 10,
                            children: [
                              for (
                                var i = 0;
                                i < c.discovery.devices.length;
                                i++
                              )
                                SizedBox(
                                  width: (box.maxWidth - 24) / 2,
                                  child: _deviceRow(
                                    c,
                                    c.discovery.devices[i],
                                    i,
                                  ),
                                ),
                            ],
                          ),
                          if (c.discovery.setupIssue != null)
                            BluetoothSetupCard(
                              issue: c.discovery.setupIssue!,
                              onHelp: () =>
                                  _update(() => _showBluetoothHelp = true),
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
                              c.discovery.error == null &&
                              c.discovery.setupIssue == null)
                            Center(
                              child: Column(
                                children: [
                                  const SizedBox(height: 6),
                                  Image.asset(
                                    'assets/devices/add-device-icon.png',
                                    width: 48,
                                    height: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  LText(
                                    'No Bluetooth devices found',
                                    style: AppTypography.text(16, 24),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 180,
                                    child: landscapeAction(
                                      'Refresh',
                                      c.refreshAutoSearch,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscapeManual(GestureController c) => SizedBox(
    height: 80,
    child: Row(
      children: [
        Image.asset(
          'assets/devices/controller-thumbnail.png',
          width: 46,
          height: 50,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LText('Gesture Control', style: AppTypography.text(14, 20)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 88,
          height: 40,
          child: _button(
            'Connect',
            () => _connect(c),
            key: const ValueKey('manual-gesture-control'),
          ),
        ),
      ],
    ),
  );

  Widget _landscapeHome(GestureController c) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(280, box.maxHeight),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText('Hello!', style: AppTypography.text(12, 18)),
                          Text(
                            c.preferences.getBool('gesture.guestSession') ==
                                    true
                                ? tr(context, 'Guest')
                                : c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.text(
                              20,
                              28,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr(context, 'Settings'),
                      onPressed: () => c.openSettings(returnTo: FlowPage.home),
                      icon: Image.asset(
                        'assets/devices/settings-button.png',
                        width: 44,
                        height: 44,
                      ),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      tooltip: tr(context, 'Profile'),
                      color: AppColors.surface,
                      onSelected: (v) {
                        if (v == 'logout') confirmLogout(context, c);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            c.preferences.getBool('gesture.guestSession') ==
                                    true
                                ? tr(context, 'Guest')
                                : c.name,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logout',
                          child: LText('Log out'),
                        ),
                      ],
                      child: CircleAvatar(
                        backgroundColor: AppColors.surface,
                        child: Text(
                          c.name.trim().isEmpty
                              ? 'G'
                              : c.name.trim().characters.first.toUpperCase(),
                          style: AppTypography.text(22, 30),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 70,
                              height: 70,
                              child: IconButton(
                                tooltip: tr(context, 'Add a device'),
                                padding: EdgeInsets.zero,
                                onPressed: () => c.chooseConnection('Auto'),
                                icon: Image.asset(
                                  'assets/devices/add-device-icon.png',
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: _button(
                                'Add Device',
                                () => c.chooseConnection('Auto'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: c.device == null
                          ? const SizedBox.shrink()
                          : Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Image.asset(
                                        'assets/devices/controller-thumbnail.png',
                                        width: 56,
                                        height: 64,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            LText(
                                              c.device!,
                                              style: AppTypography.text(16, 24),
                                            ),
                                            LText(
                                              c.trained
                                                  ? 'Saved demo setup'
                                                  : 'Continue setup',
                                              style: AppTypography.text(
                                                12,
                                                18,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  landscapeAction(
                                    'Continue setup',
                                    c.resumeSetup,
                                    secondary: true,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
