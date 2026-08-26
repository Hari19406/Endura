// lib/services/ble_cadence_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_connection_state.dart';
import 'ble_scanner_service.dart';

/// Live cadence (steps/min) from a paired BLE Running Speed and Cadence
/// sensor (footpod, or a watch that exposes the RSC profile) — GATT service
/// 0x1814, RSC Measurement characteristic 0x2A53. No phone-accelerometer
/// estimation, per project decision: real sensor data or nothing.
class BleCadenceService {
  BleCadenceService._();
  static final BleCadenceService instance = BleCadenceService._();

  static final Guid rscServiceUuid = Guid(
    '00001814-0000-1000-8000-00805f9b34fb',
  );
  static final Guid rscMeasurementCharUuid = Guid(
    '00002a53-0000-1000-8000-00805f9b34fb',
  );

  static const _prefsDeviceIdKey = 'ble_cadence_device_id';

  final _cadenceController = StreamController<int>.broadcast();
  Stream<int> get cadenceStream => _cadenceController.stream;

  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  int? lastCadence;

  Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) => BleScannerService.instance.scanForService(
    rscServiceUuid,
    timeout: timeout,
  );

  Future<void> stopScan() => BleScannerService.instance.stopScan();

  Future<bool> connect(BluetoothDevice device) async {
    _connectionController.add(BleConnectionState.connecting);
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid == rscServiceUuid,
        orElse: () => throw StateError('RSC service not found'),
      );
      final char = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == rscMeasurementCharUuid,
        orElse: () => throw StateError('RSC Measurement characteristic missing'),
      );
      await _subscribeToCadence(char);
      _device = device;
      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connectionController.add(BleConnectionState.disconnected);
        }
      });
      await _persistDeviceId(device.remoteId.str);
      _connectionController.add(BleConnectionState.connected);
      return true;
    } catch (e) {
      debugPrint('[BleCadenceService] connect failed: $e');
      _connectionController.add(BleConnectionState.disconnected);
      return false;
    }
  }

  Future<void> _subscribeToCadence(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    _valueSub?.cancel();
    _valueSub = char.lastValueStream.listen((bytes) {
      final cadence = _parseCadence(bytes);
      if (cadence == null) return;
      lastCadence = cadence;
      _cadenceController.add(cadence);
    });
  }

  /// Parses the BLE RSC Measurement characteristic per spec: byte 0 = flags,
  /// bytes 1-2 = instantaneous speed (ignored, GPS is the speed source
  /// already), byte 3 = instantaneous cadence in steps/min (uint8, always
  /// present regardless of the flags byte).
  int? _parseCadence(List<int> bytes) {
    if (bytes.length < 4) return null;
    return bytes[3];
  }

  Future<void> disconnect() async {
    await _valueSub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    lastCadence = null;
    _connectionController.add(BleConnectionState.disconnected);
  }

  Future<bool> reconnectToLastKnownDevice() async {
    final id = await _lastDeviceId();
    if (id == null) return false;
    try {
      final device = BluetoothDevice.fromId(id);
      return await connect(device);
    } catch (e) {
      debugPrint('[BleCadenceService] silent reconnect failed: $e');
      return false;
    }
  }

  Future<void> _persistDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDeviceIdKey, id);
  }

  Future<String?> _lastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsDeviceIdKey);
  }

  Future<void> forgetDevice() async {
    await disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsDeviceIdKey);
  }

  Future<String?> lastDeviceId() => _lastDeviceId();

  void dispose() {
    _valueSub?.cancel();
    _connSub?.cancel();
    _cadenceController.close();
    _connectionController.close();
  }
}
