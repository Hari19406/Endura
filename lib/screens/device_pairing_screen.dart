// lib/screens/device_pairing_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_heart_rate_service.dart';
import '../services/ble_cadence_service.dart';
import '../services/ble_connection_state.dart';
import '../theme/app_colors.dart';

enum DeviceType { heartRate, cadence }

class DevicePairingScreen extends StatefulWidget {
  final DeviceType deviceType;
  const DevicePairingScreen({super.key, required this.deviceType});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  bool _permissionDenied = false;
  bool _scanning = false;
  List<ScanResult> _results = [];
  String? _connectingId;
  BleConnectionState _connectionState = BleConnectionState.disconnected;

  String get _title => widget.deviceType == DeviceType.heartRate
      ? 'Heart rate monitor'
      : 'Running cadence sensor';

  @override
  void initState() {
    super.initState();
    _checkExistingConnection();
    _startScan();
  }

  void _checkExistingConnection() {
    final connected = widget.deviceType == DeviceType.heartRate
        ? BleHeartRateService.instance.lastBpm != null
        : BleCadenceService.instance.lastCadence != null;
    if (connected) {
      setState(() => _connectionState = BleConnectionState.connected);
    }
  }

  Future<void> _startScan() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final granted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
    if (!granted) {
      if (statuses.values.any((s) => s.isPermanentlyDenied)) {
        setState(() => _permissionDenied = true);
      }
      return;
    }

    setState(() {
      _scanning = true;
      _results = [];
    });

    final results = widget.deviceType == DeviceType.heartRate
        ? await BleHeartRateService.instance.scan()
        : await BleCadenceService.instance.scan();

    if (!mounted) return;
    setState(() {
      _scanning = false;
      _results = results;
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _connectingId = device.remoteId.str;
      _connectionState = BleConnectionState.connecting;
    });
    final ok = widget.deviceType == DeviceType.heartRate
        ? await BleHeartRateService.instance.connect(device)
        : await BleCadenceService.instance.connect(device);
    if (!mounted) return;
    setState(() {
      _connectingId = null;
      _connectionState = ok
          ? BleConnectionState.connected
          : BleConnectionState.disconnected;
    });
  }

  Future<void> _disconnect() async {
    HapticFeedback.lightImpact();
    if (widget.deviceType == DeviceType.heartRate) {
      await BleHeartRateService.instance.forgetDevice();
    } else {
      await BleCadenceService.instance.forgetDevice();
    }
    if (!mounted) return;
    setState(() => _connectionState = BleConnectionState.disconnected);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(
          _title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _permissionDenied
          ? _buildPermissionDenied(c)
          : SafeArea(
              child: Column(
                children: [
                  if (_connectionState == BleConnectionState.connected)
                    _buildConnectedBanner(c),
                  Expanded(child: _buildScanList(c)),
                ],
              ),
            ),
      floatingActionButton: _permissionDenied
          ? null
          : FloatingActionButton.extended(
              onPressed: _scanning ? null : _startScan,
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              icon: _scanning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_scanning ? 'Scanning…' : 'Scan again'),
            ),
    );
  }

  Widget _buildPermissionDenied(AppColors c) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 48, color: c.textFaint),
          const SizedBox(height: 16),
          Text(
            'Bluetooth permission needed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Endura needs Bluetooth access to find and connect to your device.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: openAppSettings,
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedBanner(AppColors c) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.success),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: c.success, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Connected',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: _disconnect,
            child: Text('Forget', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanList(AppColors c) {
    if (_scanning && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No devices found nearby. Make sure your device is on and in range, then tap Scan again.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _results[i];
        final id = r.device.remoteId.str;
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : 'Unknown device');
        final connecting = _connectingId == id;
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'RSSI ${r.rssi}',
                      style: TextStyle(fontSize: 11, color: c.textFaint),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: connecting ? null : () => _connect(r.device),
                child: connecting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.onAccent,
                        ),
                      )
                    : const Text('Connect'),
              ),
            ],
          ),
        );
      },
    );
  }
}
