// lib/services/ble_heart_rate_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_connection_state.dart';
import 'ble_scanner_service.dart';

/// Live BPM from a paired standard BLE Heart Rate Monitor (chest strap, most
/// GPS watches, some earbuds) — GATT Heart Rate Service 0x180D, Heart Rate
/// Measurement characteristic 0x2A37. No estimation: this is the actual
/// device reading or nothing.
class BleHeartRateService {
  BleHeartRateService._();
  static final BleHeartRateService instance = BleHeartRateService._();

  static final Guid heartRateServiceUuid = Guid(
    '0000180d-0000-1000-8000-00805f9b34fb',
  );
  static final Guid heartRateMeasurementCharUuid = Guid(
    '00002a37-0000-1000-8000-00805f9b34fb',
  );

  static const _prefsDeviceIdKey = 'ble_hr_device_id';

  final _bpmController = StreamController<int>.broadcast();
  Stream<int> get bpmStream => _bpmController.stream;

  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  int? lastBpm;

  Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) => BleScannerService.instance.scanForService(
    heartRateServiceUuid,
    timeout: timeout,
  );

  Future<void> stopScan() => BleScannerService.instance.stopScan();

  Future<bool> connect(BluetoothDevice device) async {
    _connectionController.add(BleConnectionState.connecting);
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid == heartRateServiceUuid,
        orElse: () => throw StateError('Heart Rate service not found'),
      );
      final char = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == heartRateMeasurementCharUuid,
        orElse: () =>
            throw StateError('Heart Rate Measurement characteristic missing'),
      );
      await _subscribeToHeartRate(char);
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
      debugPrint('[BleHeartRateService] connect failed: $e');
      _connectionController.add(BleConnectionState.disconnected);
      return false;
    }
  }

  Future<void> _subscribeToHeartRate(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    _valueSub?.cancel();
    _valueSub = char.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      final bpm = _parseHeartRateMeasurement(bytes);
      if (bpm == null) return;
      lastBpm = bpm;
      _bpmController.add(bpm);
    });
  }

  /// Parses the BLE Heart Rate Measurement characteristic per spec: bit 0 of
  /// the flags byte selects UINT8 vs UINT16 (little-endian) bpm encoding.
  int? _parseHeartRateMeasurement(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    final isUint16 = (flags & 0x01) != 0;
    if (isUint16) {
      if (bytes.length < 3) return null;
      return bytes[1] | (bytes[2] << 8);
    }
    if (bytes.length < 2) return null;
    return bytes[1];
  }

  Future<void> disconnect() async {
    await _valueSub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    lastBpm = null;
    _connectionController.add(BleConnectionState.disconnected);
  }

  /// Attempts a silent reconnect to the last-paired device (no scan UI) —
  /// called automatically at the start of a run.
  Future<bool> reconnectToLastKnownDevice() async {
    final id = await _lastDeviceId();
    if (id == null) return false;
    try {
      final device = BluetoothDevice.fromId(id);
      return await connect(device);
    } catch (e) {
      debugPrint('[BleHeartRateService] silent reconnect failed: $e');
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
    _bpmController.close();
    _connectionController.close();
  }
}
