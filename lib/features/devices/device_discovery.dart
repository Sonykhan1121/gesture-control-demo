import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DiscoveredDevice {
  const DiscoveredDevice(this.name, this.address);
  final String name, address;
}

enum BluetoothSetupIssue { poweredOff, permissionDenied, unavailable }

abstract class DeviceDiscovery extends ChangeNotifier {
  List<DiscoveredDevice> get devices;
  bool get scanning;
  String? get error;
  BluetoothSetupIssue? get setupIssue => null;
  bool get waitingForBluetooth => false;
  Future<void> restart();
  Future<void> cancelScan() => stop();
  Future<void> stop();
}

/// Small platform boundary so readiness and navigation races can be tested
/// without a radio. Device names are still filtered in BleDeviceDiscovery.
abstract class BleScanClient {
  Future<bool> get isSupported;
  Stream<BluetoothAdapterState> get adapterState;
  Stream<List<DiscoveredDevice>> get results;
  Stream<bool> get scanState;
  Future<void> startScan();
  Future<void> stopScan();
}

class FlutterBleScanClient implements BleScanClient {
  @override
  Future<bool> get isSupported => FlutterBluePlus.isSupported;
  @override
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;
  @override
  Stream<bool> get scanState => FlutterBluePlus.isScanning;
  @override
  Stream<List<DiscoveredDevice>> get results =>
      FlutterBluePlus.onScanResults.map(
        (results) => results.map((result) {
          final advertised = result.advertisementData.advName.trim();
          final name = advertised.isNotEmpty
              ? advertised
              : result.device.platformName.trim();
          return DiscoveredDevice(name, result.device.remoteId.str);
        }).toList(),
      );
  @override
  Future<void> startScan() =>
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();
}

class BleDeviceDiscovery extends DeviceDiscovery {
  BleDeviceDiscovery({BleScanClient? client, bool? waitForAdapter})
    : _client = client ?? FlutterBleScanClient(),
      _waitForAdapter =
          waitForAdapter ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  final BleScanClient _client;
  final bool _waitForAdapter;
  final _devices = <String, DiscoveredDevice>{};
  StreamSubscription<List<DiscoveredDevice>>? _results;
  StreamSubscription<bool>? _scanState;
  StreamSubscription<BluetoothAdapterState>? _adapterState;
  Future<void> _queue = Future.value();
  int _generation = 0, _attempt = 0;
  bool _disposed = false, _adapterReady = false;
  bool _scanning = false;
  String? _error;
  BluetoothSetupIssue? _setupIssue;
  bool _waitingForBluetooth = false;

  @override
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices.values);
  @override
  bool get scanning => _scanning;
  @override
  String? get error => _error;
  @override
  BluetoothSetupIssue? get setupIssue => _setupIssue;
  @override
  bool get waitingForBluetooth => _waitingForBluetooth;

  bool _current(int generation, [int? attempt]) =>
      !_disposed &&
      generation == _generation &&
      (attempt == null || attempt == _attempt);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _cancelScanListeners() async {
    await _results?.cancel();
    await _scanState?.cancel();
    _results = null;
    _scanState = null;
  }

  Future<void> _stopNative() async {
    try {
      await _client.stopScan();
    } catch (error) {
      // Off/unauthorized adapters may reject stop. That must not prevent a
      // later ready-state notification from starting the search.
      if (kDebugMode) debugPrint('Bluetooth scan cleanup: $error');
    }
  }

  @override
  Future<void> restart() {
    final generation = ++_generation;
    ++_attempt;
    _adapterReady = false;
    _devices.clear();
    _error = null;
    _setupIssue = null;
    _waitingForBluetooth = _waitForAdapter;
    _scanning = true;
    _changed();
    return _queue = _queue.then((_) async {
      if (!_current(generation)) return;
      try {
        await _adapterState?.cancel();
        _adapterState = null;
        await _cancelScanListeners();
        await _stopNative();
        if (!_current(generation)) return;
        if (!await _client.isSupported) {
          throw UnsupportedError('Bluetooth is not supported on this device');
        }
        if (!_current(generation)) return;
        if (_waitForAdapter) {
          // CoreBluetooth initially reports unknown while initializing and
          // requesting permission. Only powered-on can actually start a scan.
          _adapterState = _client.adapterState.listen(
            (state) => _onAdapterState(state, generation),
            onError: (Object error) => _failed(error, generation),
          );
        } else {
          // Android startScan requests its version-specific permissions.
          // Do not block that permission request behind an adapter wait.
          await _startScan(generation, ++_attempt);
        }
      } catch (error) {
        _failed(error, generation);
      }
    });
  }

  void _onAdapterState(BluetoothAdapterState state, int generation) {
    if (!_current(generation)) return;
    if (!_waitForAdapter &&
        (state == BluetoothAdapterState.unknown ||
            state == BluetoothAdapterState.turningOn)) {
      return;
    }
    if (state == BluetoothAdapterState.on) {
      if (_adapterReady) return; // Repeated on events are not refresh requests.
      _adapterReady = true;
      _error = null;
      _setupIssue = null;
      _waitingForBluetooth = false;
      if (!_waitForAdapter) {
        // Android keeps its explicit Refresh flow. Observing a ready adapter
        // must not duplicate a scan or permission request.
        _scanning = false;
        _changed();
        return;
      }
      _scanning = true;
      final attempt = ++_attempt;
      _changed();
      _queue = _queue.then((_) => _startScan(generation, attempt));
      return;
    }
    _adapterReady = false;
    ++_attempt; // Invalidate old scan callbacks immediately.
    _devices.clear();
    _scanning =
        state == BluetoothAdapterState.unknown ||
        state == BluetoothAdapterState.turningOn;
    _waitingForBluetooth = _scanning;
    _setupIssue = !_waitForAdapter
        ? null
        : switch (state) {
            BluetoothAdapterState.off ||
            BluetoothAdapterState.turningOff => BluetoothSetupIssue.poweredOff,
            BluetoothAdapterState.unauthorized =>
              BluetoothSetupIssue.permissionDenied,
            BluetoothAdapterState.unavailable =>
              BluetoothSetupIssue.unavailable,
            _ => null,
          };
    _error = switch (state) {
      BluetoothAdapterState.off || BluetoothAdapterState.turningOff =>
        _waitForAdapter
            ? 'Turn on Bluetooth. Search will start automatically.'
            : 'Turn on Bluetooth, then tap refresh to search.',
      BluetoothAdapterState.unauthorized =>
        _waitForAdapter
            ? 'Allow Bluetooth for lazivoo in Settings. Search will start automatically.'
            : 'Allow Bluetooth/Nearby devices permission (Location on older Android), then tap refresh.',
      BluetoothAdapterState.unavailable =>
        'Bluetooth search is not supported on this device.',
      _ => null,
    };
    _changed();
    _queue = _queue.then((_) async {
      if (!_current(generation) || _adapterReady) return;
      await _cancelScanListeners();
      await _stopNative();
    });
  }

  Future<void> _startScan(int generation, int attempt) async {
    if (!_current(generation, attempt)) return;
    try {
      await _cancelScanListeners();
      await _stopNative();
      if (!_current(generation, attempt)) return;
      _error = null;
      _setupIssue = null;
      _waitingForBluetooth = false;
      _scanning = true;
      _changed();
      _results = _client.results.listen((results) {
        if (!_current(generation, attempt) || _error != null) return;
        for (final result in results) {
          final name = result.name.trim();
          if (name.isEmpty) continue;
          _devices[result.address] = DiscoveredDevice(name, result.address);
        }
        _changed();
      }, onError: (Object error) => _failed(error, generation, attempt));
      var started = false;
      _scanState = _client.scanState.listen((active) {
        if (_current(generation, attempt) && (active || started)) {
          _scanning = active && _error == null;
          _changed();
        }
      });
      await _client.startScan();
      started = true;
      if (!_waitForAdapter && _current(generation) && _adapterState == null) {
        // Subscribe only after native startup has obtained Android permissions.
        // Keep observing after timeout too, so old Connect rows cannot survive
        // a later adapter shutdown. Denied startup never gains an auto-retry.
        _adapterReady = true;
        _adapterState = _client.adapterState.listen(
          (state) => _onAdapterState(state, generation),
          onError: (Object error) => _failed(error, generation),
        );
      }
      if (!_current(generation, attempt)) await _stopNative();
    } catch (error) {
      _failed(error, generation, attempt);
    }
  }

  void _failed(Object error, int generation, [int? attempt]) {
    if (kDebugMode) debugPrint('Bluetooth discovery failed: $error');
    if (!_current(generation, attempt)) return;
    _scanning = false;
    _waitingForBluetooth = false;
    if (_waitForAdapter) {
      final message = error.toString().toLowerCase();
      _setupIssue = error is UnsupportedError
          ? BluetoothSetupIssue.unavailable
          : message.contains('permission') || message.contains('unauthorized')
          ? BluetoothSetupIssue.permissionDenied
          : message.contains('turned on') ||
                message.contains('adapter is off') ||
                message.contains('bluetooth is off')
          ? BluetoothSetupIssue.poweredOff
          : null;
    }
    _error = _scanErrorMessage(error);
    _changed();
  }

  String _scanErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (error is UnsupportedError) {
      return 'Bluetooth search is not supported on this device.';
    }
    if (message.contains('location services')) {
      return 'Turn on Location services, then tap refresh to search.';
    }
    if (message.contains('permission') || message.contains('unauthorized')) {
      if (_waitForAdapter) {
        return 'Allow Bluetooth for lazivoo in Settings. Search will start automatically.';
      }
      return 'Allow Bluetooth/Nearby devices permission (Location on older Android), then tap refresh.';
    }
    if (message.contains('turned on') ||
        message.contains('adapter is off') ||
        message.contains('bluetooth is off')) {
      if (_waitForAdapter) {
        return 'Turn on Bluetooth. Search will start automatically.';
      }
      return 'Turn on Bluetooth, then tap refresh to search.';
    }
    return 'Unable to search. Check Bluetooth, permissions and Location services, then tap refresh.';
  }

  @override
  Future<void> cancelScan() {
    // Keep the established iOS cancellation/readiness behavior.
    if (_waitForAdapter) return stop();
    final generation = _generation;
    ++_attempt;
    _scanning = false;
    _waitingForBluetooth = false;
    _changed();
    // Keep observing the adapter while found devices are still displayed.
    // Leaving the page calls stop(), which also releases that observer.
    return _queue = _queue.then((_) async {
      if (!_current(generation)) return;
      await _cancelScanListeners();
      await _stopNative();
    });
  }

  @override
  Future<void> stop() {
    ++_generation;
    ++_attempt;
    _adapterReady = false;
    _scanning = false;
    _waitingForBluetooth = false;
    _setupIssue = null;
    _error = null;
    _changed();
    return _queue = _queue.then((_) async {
      await _adapterState?.cancel();
      _adapterState = null;
      await _cancelScanListeners();
      await _stopNative();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
