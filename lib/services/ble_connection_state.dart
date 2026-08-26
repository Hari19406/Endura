// lib/services/ble_connection_state.dart

/// Shared connection lifecycle for BLE sensor services (heart rate, cadence).
enum BleConnectionState { disconnected, scanning, connecting, connected }
