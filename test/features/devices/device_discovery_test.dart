import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';

class _BleClient implements BleScanClient {
  final states = StreamController<BluetoothAdapterState>.broadcast(sync: true);
  final devices = StreamController<List<DiscoveredDevice>>.broadcast(
    sync: true,
  );
  final scanning = StreamController<bool>.broadcast(sync: true);
  BluetoothAdapterState current = BluetoothAdapterState.unknown;
  int starts = 0, stops = 0;
  bool supported = true;
  Completer<void>? startGate;
  Object? startError;
  bool? listenerAtFirstStart;

  void state(BluetoothAdapterState state) {
    current = state;
    states.add(state);
  }

  @override
  Future<bool> get isSupported async => supported;
  @override
  Stream<BluetoothAdapterState> get adapterState async* {
    yield current;
    yield* states.stream;
  }

  @override
  Stream<List<DiscoveredDevice>> get results => devices.stream;
  @override
  Stream<bool> get scanState async* {
    yield false; // The plugin's initial cached value before startScan.
    yield* scanning.stream;
  }

  @override
  Future<void> startScan() async {
    starts++;
    if (starts == 1) listenerAtFirstStart = states.hasListener;
    await startGate?.future;
    if (startError != null) throw startError!;
    scanning.add(true);
  }

  @override
  Future<void> stopScan() async {
    stops++;
    scanning.add(false);
  }

  Future<void> close() async {
    await states.close();
    await devices.close();
    await scanning.close();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _BleClient client;
  late BleDeviceDiscovery discovery;
  setUp(() {
    client = _BleClient();
    discovery = BleDeviceDiscovery(client: client, waitForAdapter: true);
  });
  tearDown(() async {
    await discovery.stop();
    discovery.dispose();
    await _settle();
    await client.close();
  });

  test(
    'iOS waits for unknown to become on and starts once without refresh',
    () async {
      await discovery.restart();
      await _settle();
      expect(client.starts, 0);
      expect(discovery.error, isNull);
      expect(discovery.setupIssue, isNull);
      expect(discovery.waitingForBluetooth, isTrue);
      expect(discovery.scanning, isTrue);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
      expect(discovery.scanning, isTrue);
      expect(discovery.waitingForBluetooth, isFalse);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
      client.devices.add(const [
        DiscoveredDevice(' ', 'anonymous'),
        DiscoveredDevice(' Stand ', 'device'),
      ]);
      expect(discovery.devices.single.name, 'Stand');
    },
  );

  test(
    'off and permission denial recover automatically when Bluetooth becomes ready',
    () async {
      client.current = BluetoothAdapterState.off;
      await discovery.restart();
      await _settle();
      expect(discovery.error, contains('automatically'));
      expect(discovery.setupIssue, BluetoothSetupIssue.poweredOff);
      expect(discovery.scanning, isFalse);
      expect(client.starts, 0);
      client.state(BluetoothAdapterState.unauthorized);
      expect(discovery.error, contains('Settings'));
      expect(discovery.setupIssue, BluetoothSetupIssue.permissionDenied);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
      expect(discovery.error, isNull);
      expect(discovery.setupIssue, isNull);
      client.devices.add(const [DiscoveredDevice('Stand', 'device')]);
      client.state(BluetoothAdapterState.off);
      expect(discovery.devices, isEmpty);
      expect(discovery.scanning, isFalse);
      await _settle();
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 2);
    },
  );

  test(
    'normal scan completion does not restart on duplicate on notifications',
    () async {
      client.current = BluetoothAdapterState.on;
      await discovery.restart();
      await _settle();
      client.scanning.add(false);
      expect(discovery.scanning, isFalse);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
      await discovery.restart();
      await _settle();
      expect(client.starts, 2);
      expect(client.states.hasListener, isTrue);
    },
  );

  test(
    'leaving while waiting removes the readiness listener and cannot start later',
    () async {
      await discovery.restart();
      await _settle();
      await discovery.stop();
      expect(client.states.hasListener, isFalse);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 0);
      expect(discovery.scanning, isFalse);
    },
  );

  test(
    'refresh and rapid adapter changes cannot start obsolete attempts',
    () async {
      await discovery.restart();
      await _settle();
      client.state(BluetoothAdapterState.on);
      client.state(BluetoothAdapterState.off);
      await discovery.restart();
      await _settle();
      expect(client.starts, 0);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
    },
  );

  test(
    'leaving during native scan startup discards results and stops that scan',
    () async {
      client.current = BluetoothAdapterState.on;
      client.startGate = Completer<void>();
      await discovery.restart();
      await _settle();
      expect(client.starts, 1);
      final stopped = discovery.stop();
      client.devices.add(const [DiscoveredDevice('Stale', 'device')]);
      expect(discovery.devices, isEmpty);
      client.startGate!.complete();
      await stopped;
      expect(discovery.scanning, isFalse);
      expect(client.devices.hasListener, isFalse);
      expect(client.states.hasListener, isFalse);
    },
  );

  test(
    'Android retains native permission-triggering startup without iOS readiness wait',
    () async {
      final android = BleDeviceDiscovery(client: client, waitForAdapter: false);
      await android.restart();
      await _settle();
      expect(client.starts, 1);
      expect(client.listenerAtFirstStart, isFalse);
      expect(client.states.hasListener, isTrue);
      expect(android.scanning, isTrue);
      await android.stop();
      android.dispose();
      await _settle();
    },
  );

  test(
    'Android observes radio off, rejects stale results, and requires refresh after on',
    () async {
      client.current = BluetoothAdapterState.on;
      final android = BleDeviceDiscovery(client: client, waitForAdapter: false);
      await android.restart();
      await _settle();
      client.devices.add(const [DiscoveredDevice('Stand', 'device')]);
      expect(android.devices, hasLength(1));
      client.state(BluetoothAdapterState.turningOff);
      expect(android.devices, isEmpty);
      expect(android.scanning, isFalse);
      expect(android.error, contains('Turn on Bluetooth'));
      expect(
        android.setupIssue,
        isNull,
        reason:
            'Android keeps the centered error instead of the iOS settings card',
      );
      client.devices.add(const [DiscoveredDevice('Late', 'stale')]);
      client.scanning.add(true);
      expect(android.devices, isEmpty);
      expect(android.scanning, isFalse);
      await _settle();
      client.state(BluetoothAdapterState.off);
      await _settle();
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(android.error, isNull);
      expect(android.scanning, isFalse);
      expect(client.starts, 1);
      await android.restart();
      await _settle();
      expect(client.starts, 2);
      await android.stop();
      expect(client.states.hasListener, isFalse);
      client.state(BluetoothAdapterState.off);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 2);
      android.dispose();
      await _settle();
    },
  );

  test(
    'Android still clears results if radio is disabled after scan timeout',
    () async {
      client.current = BluetoothAdapterState.on;
      final android = BleDeviceDiscovery(client: client, waitForAdapter: false);
      await android.restart();
      await _settle();
      client.devices.add(const [DiscoveredDevice('Stand', 'device')]);
      client.scanning.add(false);
      expect(android.devices, hasLength(1));
      client.state(BluetoothAdapterState.off);
      await _settle();
      expect(android.devices, isEmpty);
      expect(android.error, contains('Turn on Bluetooth'));
      await android.stop();
      android.dispose();
      await _settle();
    },
  );

  test('Android cancel keeps radio monitoring until leaving', () async {
    client.current = BluetoothAdapterState.on;
    await discovery.stop();
    discovery = BleDeviceDiscovery(client: client, waitForAdapter: false);
    await discovery.restart();
    await _settle();
    client.devices.add(const [DiscoveredDevice('Stand', 'device')]);
    await discovery.cancelScan();
    expect(discovery.scanning, isFalse);
    expect(discovery.devices, hasLength(1));
    expect(client.states.hasListener, isTrue);
    client.state(BluetoothAdapterState.off);
    expect(discovery.devices, isEmpty);
    expect(discovery.error, contains('Turn on Bluetooth'));
    client.state(BluetoothAdapterState.on);
    await _settle();
    expect(client.starts, 1, reason: 'Cancel must prevent auto-restarting');
    await discovery.restart();
    await _settle();
    expect(client.starts, 2);
    await discovery.stop();
    expect(client.states.hasListener, isFalse);
  });
  test(
    'cancel during iOS readiness prevents an eventual automatic scan',
    () async {
      await discovery.restart();
      await discovery.cancelScan();
      client.state(BluetoothAdapterState.turningOn);
      expect(discovery.scanning, isFalse);
      expect(discovery.waitingForBluetooth, isFalse);
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 0);
      await discovery.restart();
      await _settle();
      expect(client.starts, 1);
    },
  );

  test(
    'cancel during Android native startup retains radio monitoring',
    () async {
      await discovery.stop();
      client.current = BluetoothAdapterState.on;
      client.startGate = Completer<void>();
      discovery = BleDeviceDiscovery(client: client, waitForAdapter: false);
      final starting = discovery.restart();
      await _settle();
      client.devices.add(const [DiscoveredDevice('Stand', 'device')]);
      final cancelling = discovery.cancelScan();
      client.startGate!.complete();
      await starting;
      await cancelling;
      await _settle();
      expect(client.states.hasListener, isTrue);
      expect(discovery.scanning, isFalse);
      client.state(BluetoothAdapterState.off);
      expect(discovery.devices, isEmpty);
    },
  );

  test(
    'Android permission denial does not attach an observer or auto-request again',
    () async {
      client.current = BluetoothAdapterState.on;
      client.startError = StateError('permission denied');
      final android = BleDeviceDiscovery(client: client, waitForAdapter: false);
      await android.restart();
      await _settle();
      expect(client.starts, 1);
      expect(client.states.hasListener, isFalse);
      expect(android.error, contains('permission'));
      client.state(BluetoothAdapterState.on);
      await _settle();
      expect(client.starts, 1);
      client.startError = null;
      await android.restart();
      await _settle();
      expect(client.starts, 2);
      expect(client.states.hasListener, isTrue);
      await android.stop();
      android.dispose();
      await _settle();
    },
  );

  test(
    'unsupported adapter and failed scan have explicit errors and refresh can retry',
    () async {
      client.supported = false;
      await discovery.restart();
      expect(discovery.error, contains('not supported'));
      expect(discovery.scanning, isFalse);
      client.supported = true;
      client.current = BluetoothAdapterState.on;
      client.startError = StateError('temporary scan failure');
      await discovery.restart();
      await _settle();
      expect(discovery.error, contains('Unable to search'));
      client.startError = null;
      await discovery.restart();
      await _settle();
      expect(discovery.error, isNull);
      expect(discovery.scanning, isTrue);
    },
  );
}
